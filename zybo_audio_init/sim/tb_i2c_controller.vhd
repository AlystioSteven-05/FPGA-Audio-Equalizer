library ieee;
use ieee.std_logic_1164.all;

entity tb_i2c_controller is
end entity;

architecture sim of tb_i2c_controller is
    signal clk       : std_logic := '0';
    signal reset     : std_logic := '1';
    signal start     : std_logic := '0';
    signal data_word : std_logic_vector(15 downto 0) := x"0812";
    signal busy      : std_logic;
    signal done      : std_logic;
    signal ack_error : std_logic;
    signal scl       : std_logic;
    signal sda       : std_logic;
    signal slave_ack : std_logic := '0';
    signal ack_count : natural := 0;
begin
    clk <= not clk after 5 ns; -- 100 MHz

    -- Simulated bus pull-up and slave open-drain ACK driver.
    sda <= 'H';
    sda <= '0' when slave_ack = '1' else 'Z';

    dut: entity work.i2c_controller
        generic map (CLK_HZ => 1_000_000, I2C_HZ => 100_000)
        port map (
            clk => clk, reset => reset, start => start,
            data_word => data_word, busy => busy, done => done,
            ack_error => ack_error, scl => scl, sda => sda
        );

    slave_model: process
    begin
        loop
            -- Each I2C byte contains 8 data bits followed by one ACK bit.
            for bit_no in 0 to 7 loop
                wait until rising_edge(scl);
            end loop;
            wait until falling_edge(scl);
            slave_ack <= '1';
            wait until rising_edge(scl);
            ack_count <= ack_count + 1;
            wait until falling_edge(scl);
            slave_ack <= '0';
        end loop;
    end process;

    stimulus: process
    begin
        wait for 100 ns;
        wait until rising_edge(clk);
        reset <= '0';
        wait for 100 ns;

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        wait until done = '1' for 2 ms;
        assert done = '1'
            report "I2C transaction timed out" severity failure;
        wait for 20 ns;

        assert ack_error = '0'
            report "I2C controller detected a NACK" severity failure;
        assert busy = '0'
            report "I2C busy did not clear" severity failure;
        assert ack_count = 3
            report "Expected ACKs for address and two data bytes" severity failure;

        report "tb_i2c_controller PASS" severity note;
        wait;
    end process;
end architecture;
