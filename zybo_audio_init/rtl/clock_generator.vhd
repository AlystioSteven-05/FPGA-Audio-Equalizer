library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Divides the exact 12.288 MHz MCLK supplied by clk_wiz_audio.
-- BCLK = MCLK/4 = 3.072 MHz.
-- LRCLK = MCLK/256 = 48 kHz, with 32 BCLK periods per channel slot.
entity clock_generator is
    port (
        mclk_in    : in  std_logic;
        reset      : in  std_logic; -- active high, synchronous to mclk_in
        mclk       : out std_logic;
        bclk       : out std_logic;
        pblrc      : out std_logic;
        reclrc     : out std_logic;
        sample_tick: out std_logic  -- one pulse per stereo frame (48 kHz)
    );
end entity;

architecture rtl of clock_generator is
    signal reset_sync      : std_logic_vector(2 downto 0) := (others => '1');
    signal reset_mclk      : std_logic;
    signal bclk_div_count  : natural range 0 to 1 := 0;
    signal lrclk_count     : natural range 0 to 127 := 0;
    signal bclk_reg        : std_logic := '0';
    signal lrclk_reg       : std_logic := '0';
    signal sample_tick_reg : std_logic := '0';
begin
    mclk        <= mclk_in;
    bclk        <= bclk_reg;
    pblrc       <= lrclk_reg;
    reclrc      <= lrclk_reg;
    sample_tick <= sample_tick_reg;

    -- Asynchronous assertion, synchronous deassertion in the MCLK domain.
    process(mclk_in, reset)
    begin
        if reset = '1' then
            reset_sync <= (others => '1');
        elsif rising_edge(mclk_in) then
            reset_sync <= reset_sync(1 downto 0) & '0';
        end if;
    end process;

    reset_mclk <= reset_sync(2);

    process(mclk_in)
    begin
        if rising_edge(mclk_in) then
            sample_tick_reg <= '0';

            if reset_mclk = '1' then
                bclk_div_count  <= 0;
                lrclk_count     <= 0;
                bclk_reg        <= '0';
                lrclk_reg       <= '0';
                sample_tick_reg <= '0';
            else
                -- Toggle BCLK every 2 MCLK cycles:
                -- complete BCLK period = 4 MCLK cycles.
                if bclk_div_count = 1 then
                    bclk_div_count <= 0;
                    bclk_reg <= not bclk_reg;
                else
                    bclk_div_count <= bclk_div_count + 1;
                end if;

                -- Toggle LRCLK every 128 MCLK cycles.
                -- Complete LRCLK period = 256 MCLK cycles = 48 kHz.
                if lrclk_count = 127 then
                    lrclk_count <= 0;
                    lrclk_reg <= not lrclk_reg;

                    -- Pulse once on the high-to-low frame boundary.
                    if lrclk_reg = '1' then
                        sample_tick_reg <= '1';
                    end if;
                else
                    lrclk_count <= lrclk_count + 1;
                end if;
            end if;
        end if;
    end process;
end architecture;
