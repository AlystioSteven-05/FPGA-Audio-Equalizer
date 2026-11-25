library ieee;
use ieee.std_logic_1164.all;

entity tb_ssm2603_config is
end entity;

architecture sim of tb_ssm2603_config is
    signal clk           : std_logic := '0';
    signal reset         : std_logic := '1';
    signal start_config  : std_logic := '0';
    signal i2c_start     : std_logic;
    signal i2c_data      : std_logic_vector(15 downto 0);
    signal i2c_busy      : std_logic;
    signal i2c_done      : std_logic;
    signal i2c_ack_error : std_logic;
    signal config_busy   : std_logic;
    signal config_done   : std_logic;
    signal config_error  : std_logic;
    signal scl           : std_logic;
    signal sda           : std_logic;
    signal slave_ack     : std_logic := '0';
    signal transaction_count : natural := 0;
begin
    clk <= not clk after 500 ns; -- 1 MHz
    sda <= 'H';
    sda <= '0' when slave_ack = '1' else 'Z';

    i2c: entity work.i2c_controller
        generic map (CLK_HZ => 1_000_000, I2C_HZ => 100_000)
        port map (
            clk => clk, reset => reset, start => i2c_start,
            data_word => i2c_data, busy => i2c_busy, done => i2c_done,
            ack_error => i2c_ack_error, scl => scl, sda => sda
        );

    config: entity work.ssm2603_config
        generic map (CLK_HZ => 1_000_000, VMID_DELAY_MS => 2)
        port map (
            clk => clk, reset => reset, start_config => start_config,
            i2c_start => i2c_start, i2c_data => i2c_data,
            i2c_done => i2c_done, i2c_ack_error => i2c_ack_error,
            config_busy => config_busy, config_done => config_done,
            config_error => config_error
        );

    slave_model: process
    begin
        loop
            for bit_no in 0 to 7 loop
                wait until rising_edge(scl);
            end loop;
            wait until falling_edge(scl);
            slave_ack <= '1';
            wait until rising_edge(scl);
            wait until falling_edge(scl);
            slave_ack <= '0';
        end loop;
    end process;

    transaction_monitor: process(sda)
    begin
        if falling_edge(sda) and scl = '1' then
            transaction_count <= transaction_count + 1;
        end if;
    end process;

    stimulus: process
    begin
        wait for 5 us;
        wait until rising_edge(clk);
        reset <= '0';
        wait for 5 us;
        start_config <= '1';
        wait until rising_edge(clk);
        start_config <= '0';

        wait until config_done = '1' for 20 ms;
        assert config_done = '1'
            report "Codec initialization timed out" severity failure;
        assert config_error = '0'
            report "Codec initialization reported an I2C error" severity failure;
        assert transaction_count = 12
            report "Expected 12 codec register writes" severity failure;

        report "tb_ssm2603_config PASS" severity note;
        wait;
    end process;
end architecture;
