library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- SSM2603 initialization sequencer for 12.288 MHz MCLK / 48 kHz.
-- i2c_data is a 16-bit codec control word:
-- [15:9] register address, [8:0] register data.
entity ssm2603_config is
    generic (
        CLK_HZ       : positive := 100_000_000;
        VMID_DELAY_MS: positive := 100
    );
    port (
        clk          : in  std_logic;
        reset        : in  std_logic; -- active high
        start_config : in  std_logic;
        i2c_start    : out std_logic;
        i2c_data     : out std_logic_vector(15 downto 0);
        i2c_done     : in  std_logic;
        i2c_ack_error: in  std_logic;
        config_busy  : out std_logic;
        config_done  : out std_logic; -- remains high until reset
        config_error : out std_logic  -- remains high until reset
    );
end entity;

architecture rtl of ssm2603_config is
    type rom_t is array (0 to 11) of std_logic_vector(15 downto 0);

    -- Register write words. Address is in bits 15:9; data is in bits 8:0.
    -- R6 first powers the required blocks while holding OUT powered down.
    -- R4 selects the DAC path and disables analog bypass.
    -- R7 = I2S, 24-bit, slave mode. R8 = normal mode, 48 kHz at 12.288 MHz.
    constant INIT_ROM : rom_t := (
        0  => x"1E00", -- R15: software reset
        1  => x"0C72", -- R6: external MCLK, OUT held powered down
        2  => x"0017", -- R0: left line input, 0 dB, unmuted
        3  => x"0217", -- R1: right line input, 0 dB, unmuted
        4  => x"0479", -- R2: left headphone volume, 0 dB
        5  => x"0679", -- R3: right headphone volume, 0 dB
        6  => x"0812", -- R4: DAC selected, line input to ADC, mic muted
        7  => x"0A00", -- R5: DAC unmuted, ADC HPF enabled, no de-emphasis
        8  => x"0E0A", -- R7: I2S, 24-bit, slave mode
        9  => x"1000", -- R8: 12.288 MHz / 256 = 48 kHz, normal mode
        10 => x"1201", -- R9: activate digital core
        11 => x"0C62"  -- R6: enable output after VMID settling delay
    );

    constant DELAY_CYCLES : positive :=
        (CLK_HZ / 1000) * VMID_DELAY_MS;

    type state_t is (IDLE, ISSUE, WAIT_I2C, WAIT_VMID, COMPLETE, ERROR_STATE);
    signal state      : state_t := IDLE;
    signal index      : natural range 0 to 11 := 0;
    signal delay_count: natural range 0 to DELAY_CYCLES-1 := 0;
    signal i2c_start_reg : std_logic := '0';
    signal i2c_data_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal busy_reg      : std_logic := '0';
    signal done_reg      : std_logic := '0';
    signal error_reg     : std_logic := '0';
begin
    i2c_start   <= i2c_start_reg;
    i2c_data    <= i2c_data_reg;
    config_busy <= busy_reg;
    config_done <= done_reg;
    config_error<= error_reg;

    process(clk)
    begin
        if rising_edge(clk) then
            i2c_start_reg <= '0';

            if reset = '1' then
                state         <= IDLE;
                index         <= 0;
                delay_count   <= 0;
                i2c_start_reg <= '0';
                i2c_data_reg  <= (others => '0');
                busy_reg      <= '0';
                done_reg      <= '0';
                error_reg     <= '0';
            else
                case state is
                    when IDLE =>
                        busy_reg <= '0';
                        if start_config = '1' then
                            index    <= 0;
                            busy_reg <= '1';
                            state    <= ISSUE;
                        end if;

                    when ISSUE =>
                        i2c_data_reg  <= INIT_ROM(index);
                        i2c_start_reg <= '1';
                        state         <= WAIT_I2C;

                    when WAIT_I2C =>
                        if i2c_done = '1' then
                            if i2c_ack_error = '1' then
                                error_reg <= '1';
                                busy_reg  <= '0';
                                state     <= ERROR_STATE;
                            elsif index = 9 then
                                -- Allow the VMID capacitor to settle before
                                -- activating R9 and enabling the output stage.
                                delay_count <= 0;
                                state <= WAIT_VMID;
                            elsif index = 11 then
                                busy_reg <= '0';
                                done_reg <= '1';
                                state <= COMPLETE;
                            else
                                index <= index + 1;
                                state <= ISSUE;
                            end if;
                        end if;

                    when WAIT_VMID =>
                        if delay_count = DELAY_CYCLES-1 then
                            index <= 10;
                            state <= ISSUE;
                        else
                            delay_count <= delay_count + 1;
                        end if;

                    when COMPLETE =>
                        busy_reg <= '0';
                        done_reg <= '1';

                    when ERROR_STATE =>
                        busy_reg  <= '0';
                        error_reg <= '1';

                    when others =>
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;
end architecture;
