library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- SSM2603 write-only I2C master.
-- Sends: 0x34 (7-bit address 0x1A + write bit), then two bytes
-- containing {register_address[6:0], register_data[8:0]}.
entity i2c_controller is
    generic (
        CLK_HZ : positive := 100_000_000;
        I2C_HZ : positive := 100_000
    );
    port (
        clk       : in    std_logic;
        reset     : in    std_logic; -- active high
        start     : in    std_logic; -- pulse for one clk cycle
        data_word : in    std_logic_vector(15 downto 0);
        busy      : out   std_logic;
        done      : out   std_logic; -- one clk-cycle pulse
        ack_error : out   std_logic; -- sticky until next start/reset
        scl       : out   std_logic;
        sda       : inout std_logic
    );
end entity;

architecture rtl of i2c_controller is
    constant HALF_PERIOD : positive := CLK_HZ / (2 * I2C_HZ);

    type state_t is (
        IDLE, START_A, START_B, BIT_LOW, BIT_HIGH,
        ACK_LOW, ACK_HIGH, STOP_LOW, STOP_HIGH, STOP_RELEASE
    );

    signal state       : state_t := IDLE;
    signal div_count   : natural range 0 to HALF_PERIOD-1 := 0;
    signal data_latched: std_logic_vector(15 downto 0) := (others => '0');
    signal shift_byte  : std_logic_vector(7 downto 0) := (others => '0');
    signal byte_index  : natural range 0 to 2 := 0;
    signal bit_index   : natural range 0 to 7 := 7;
    signal scl_reg     : std_logic := '1';
    signal sda_drive_low : std_logic := '0';
    signal busy_reg    : std_logic := '0';
    signal done_reg    : std_logic := '0';
    signal ack_error_reg : std_logic := '0';
begin
    scl <= scl_reg;
    -- Open-drain SDA: drive only low; release the line for logic high.
    sda <= '0' when sda_drive_low = '1' else 'Z';

    busy      <= busy_reg;
    done      <= done_reg;
    ack_error <= ack_error_reg;

    process(clk)
    begin
        if rising_edge(clk) then
            done_reg <= '0';

            if reset = '1' then
                state          <= IDLE;
                div_count      <= 0;
                data_latched   <= (others => '0');
                shift_byte     <= (others => '0');
                byte_index     <= 0;
                bit_index      <= 7;
                scl_reg        <= '1';
                sda_drive_low  <= '0';
                busy_reg       <= '0';
                done_reg       <= '0';
                ack_error_reg  <= '0';
            else
                if state = IDLE then
                    scl_reg       <= '1';
                    sda_drive_low <= '0';
                    busy_reg      <= '0';
                    div_count     <= 0;

                    if start = '1' then
                        data_latched  <= data_word;
                        shift_byte    <= x"34"; -- SSM2603 address 0x1A, write
                        byte_index    <= 0;
                        bit_index     <= 7;
                        ack_error_reg <= '0';
                        busy_reg      <= '1';
                        state         <= START_A;
                    end if;
                else
                    if div_count = HALF_PERIOD-1 then
                        div_count <= 0;

                        case state is
                            when START_A =>
                                scl_reg       <= '1';
                                sda_drive_low <= '0';
                                state         <= START_B;

                            when START_B =>
                                -- START: SDA falls while SCL is high.
                                scl_reg       <= '1';
                                sda_drive_low <= '1';
                                state         <= BIT_LOW;

                            when BIT_LOW =>
                                scl_reg <= '0';
                                if shift_byte(bit_index) = '0' then
                                    sda_drive_low <= '1';
                                else
                                    sda_drive_low <= '0';
                                end if;
                                state <= BIT_HIGH;

                            when BIT_HIGH =>
                                scl_reg <= '1';
                                if bit_index = 0 then
                                    state <= ACK_LOW;
                                else
                                    bit_index <= bit_index - 1;
                                    state <= BIT_LOW;
                                end if;

                            when ACK_LOW =>
                                scl_reg       <= '0';
                                sda_drive_low <= '0'; -- release for slave ACK
                                state         <= ACK_HIGH;

                            when ACK_HIGH =>
                                scl_reg <= '1';
                                if sda /= '0' then
                                    ack_error_reg <= '1';
                                end if;

                                if byte_index = 0 then
                                    shift_byte <= data_latched(15 downto 8);
                                    byte_index <= 1;
                                    bit_index  <= 7;
                                    state      <= BIT_LOW;
                                elsif byte_index = 1 then
                                    shift_byte <= data_latched(7 downto 0);
                                    byte_index <= 2;
                                    bit_index  <= 7;
                                    state      <= BIT_LOW;
                                else
                                    state <= STOP_LOW;
                                end if;

                            when STOP_LOW =>
                                scl_reg       <= '0';
                                sda_drive_low <= '1';
                                state         <= STOP_HIGH;

                            when STOP_HIGH =>
                                scl_reg       <= '1';
                                sda_drive_low <= '1';
                                state         <= STOP_RELEASE;

                            when STOP_RELEASE =>
                                -- STOP: SDA rises while SCL is high.
                                scl_reg       <= '1';
                                sda_drive_low <= '0';
                                busy_reg      <= '0';
                                done_reg      <= '1';
                                state         <= IDLE;

                            when others =>
                                state <= IDLE;
                        end case;
                    else
                        div_count <= div_count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
