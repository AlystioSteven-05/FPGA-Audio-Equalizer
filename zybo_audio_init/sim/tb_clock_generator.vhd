library ieee;
use ieee.std_logic_1164.all;

entity tb_clock_generator is
end entity;

architecture sim of tb_clock_generator is
    signal mclk_in     : std_logic := '0';
    signal reset       : std_logic := '1';
    signal mclk        : std_logic;
    signal bclk        : std_logic;
    signal pblrc       : std_logic;
    signal reclrc      : std_logic;
    signal sample_tick : std_logic;
    constant MCLK_PERIOD : time := 81.3802 ns; -- 12.288 MHz nominal
begin
    mclk_in <= not mclk_in after MCLK_PERIOD/2;

    dut: entity work.clock_generator
        port map (
            mclk_in => mclk_in, reset => reset, mclk => mclk,
            bclk => bclk, pblrc => pblrc, reclrc => reclrc,
            sample_tick => sample_tick
        );

    stimulus: process
        variable t1, t2 : time;
    begin
        wait for 10*MCLK_PERIOD;
        wait until rising_edge(mclk_in);
        reset <= '0';

        wait until rising_edge(bclk);
        t1 := now;
        wait until rising_edge(bclk);
        t2 := now;
        assert (t2-t1) = 4*MCLK_PERIOD
            report "BCLK period is not MCLK/4" severity failure;

        wait until rising_edge(pblrc);
        t1 := now;
        wait until rising_edge(pblrc);
        t2 := now;
        assert (t2-t1) = 256*MCLK_PERIOD
            report "LRCLK period is not MCLK/256 (48 kHz)" severity failure;

        assert pblrc = reclrc
            report "Playback and record LRCLK outputs differ" severity failure;

        report "tb_clock_generator PASS" severity note;
        wait;
    end process;
end architecture;
