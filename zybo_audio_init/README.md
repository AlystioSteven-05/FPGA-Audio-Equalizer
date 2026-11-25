# Zybo Z7-10 Audio Equalizer — Stage 1 (Clock + SSM2603 I2C)

This package contains the first three VHDL modules and their simulation testbenches:

- `rtl/clock_generator.vhd`
- `rtl/i2c_controller.vhd`
- `rtl/ssm2603_config.vhd`
- `sim/tb_clock_generator.vhd`
- `sim/tb_i2c_controller.vhd`
- `sim/tb_ssm2603_config.vhd`

## Design assumptions

- Board: Digilent Zybo Z7-10, Zynq part XC7Z010-1CLG400C.
- Audio codec: onboard SSM2603.
- Codec control address: 7-bit `0x1A`; write address byte `0x34`.
- Codec register words: `{register_address[6:0], register_data[8:0]}`.
- Audio MCLK: 12.288 MHz.
- Audio BCLK: 3.072 MHz.
- Audio frame clock: 48 kHz; 32 BCLK periods per channel slot.
- I2C clock: 100 kHz.
- Codec audio format: I2S, 24-bit, slave mode.
- The SSM2603 MUTE pin is active-low; drive it high to unmute.

## Important clocking correction

Do not assume the 125 MHz PL clock can be divided by an integer to produce 12.288 MHz. For this implementation, use the Zynq Processing System's `FCLK_CLK0` at 100 MHz as the Clocking Wizard input.

### Clocking Wizard settings

In Vivado IP Integrator:

1. Add `ZYNQ7 Processing System`.
2. Apply the Zybo Z7-10 board preset if available.
3. Enable `FCLK_CLK0` and set it to 100 MHz.
4. Add `Clocking Wizard`, instance name `clk_wiz_audio`.
5. Set the input clock to 100 MHz.
6. Enable one output clock at exactly 12.288 MHz.
7. Use the MMCM implementation and let Vivado calculate/validate the settings.
8. A mathematically valid 7-series MMCM solution is:
   - DIVCLK_DIVIDE = 5
   - CLKFBOUT_MULT_F = 48.000
   - CLKOUT0_DIVIDE_F = 78.125
   - VCO = 960 MHz
   - Output = 12.288 MHz
9. If your Clocking Wizard version rejects this configuration, use its frequency search and confirm the generated output is exactly 12.288 MHz. Do not silently accept a nearby frequency.
10. Connect `clk_wiz_audio/clk_out1` to `clock_generator/mclk_in`.

The `clock_generator` module in this package is the fabric divider after the Clocking Wizard. It does not instantiate the Clocking Wizard IP itself.

## Vivado integration

### A. Create project

- Create an RTL project for Zybo Z7-10.
- Device: `xc7z010clg400-1`.
- Add the three files under `rtl/` as Design Sources.
- Add the three files under `sim/` as Simulation Sources.

### B. Create Block Design

1. Create a Block Design.
2. Add `ZYNQ7 Processing System`.
3. Apply the Zybo Z7-10 board preset.
4. Enable `FCLK_CLK0`, set to 100 MHz.
5. Add `Clocking Wizard` and configure 100 MHz input -> 12.288 MHz output.
6. Add `Processor System Reset`.
7. Connect PS `FCLK_CLK0` to the Clocking Wizard input and to the I2C/config clock inputs.
8. Connect Clocking Wizard `locked` to the reset block's `dcm_locked`.
9. Connect the reset block's `slowest_sync_clk` to `FCLK_CLK0`.
10. Connect reset block `peripheral_reset` to the active-high `reset` inputs of the VHDL modules.
11. Add the three VHDL modules to the block design using **Add Module**:
    - `clock_generator`
    - `i2c_controller`
    - `ssm2603_config`
12. Connect Clocking Wizard `clk_out1` to `clock_generator.mclk_in`.
13. Connect `FCLK_CLK0` to `i2c_controller.clk` and `ssm2603_config.clk`.
14. Connect `i2c_start`, `i2c_data`, `i2c_done`, and `i2c_ack_error` between the configuration sequencer and I2C controller.
15. Connect I2C `scl` and `sda` to external ports.
16. Connect `mclk`, `bclk`, `pblrc`, and `reclrc` to external ports.
17. For an initial automatic boot test, tie `start_config` high. The sequencer enters COMPLETE or ERROR and does not restart until reset.
18. Export the required audio ports from the block design.

The VHDL modules are written as reusable RTL blocks. The Block Design is responsible for wiring the Clock Wizard and Zynq clocks/resets.

### C. Audio XDC pins

Use these Zybo Z7 audio pins from Digilent's reference manual:

```tcl
set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports ac_bclk]
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports ac_mclk]
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports ac_muten]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports ac_pbdat]
set_property -dict { PACKAGE_PIN T19 IOSTANDARD LVCMOS33 } [get_ports ac_pblrc]
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports ac_recdat]
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports ac_reclrc]
set_property -dict { PACKAGE_PIN N18 IOSTANDARD LVCMOS33 } [get_ports ac_scl]
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports ac_sda]
```

At this stage, `ac_pbdat` and `ac_recdat` are not used by these three modules. They will be connected when the I2S receiver/transmitter are added. `ac_muten` should be driven high only after codec initialization has completed.

The XDC above assumes the top-level external ports are named exactly as shown. If your block design exports different names, update the `get_ports` names accordingly.

### D. I2C SDA electrical handling

- SDA is open-drain: the controller drives low or releases to `Z`.
- Never drive SDA high from the FPGA.
- The physical I2C bus needs a pull-up to 3.3 V. Confirm the board's pull-up arrangement before hardware testing.
- SCL is driven by the FPGA as a push-pull output; the SSM2603 does not require clock stretching for this write sequence.

## Codec initialization sequence

The configuration ROM writes:

| Index | Register | Value | Purpose |
|---:|---:|---:|---|
| 0 | R15 | 0x000 | Software reset |
| 1 | R6 | 0x072 | Power blocks, hold output off |
| 2 | R0 | 0x017 | Left line input 0 dB, unmuted |
| 3 | R1 | 0x017 | Right line input 0 dB, unmuted |
| 4 | R2 | 0x079 | Left headphone 0 dB |
| 5 | R3 | 0x079 | Right headphone 0 dB |
| 6 | R4 | 0x012 | Select DAC output, disable bypass |
| 7 | R5 | 0x000 | DAC unmuted, ADC HPF enabled |
| 8 | R7 | 0x00A | I2S, 24-bit, slave |
| 9 | R8 | 0x000 | 48 kHz at 12.288 MHz |
| — | — | — | 100 ms VMID settling delay |
| 10 | R9 | 0x001 | Activate digital core |
| 11 | R6 | 0x062 | Enable output stage |

The VMID delay is set to 100 ms by default. This is conservative for the board's VMID decoupling network; verify against the actual board schematic and codec datasheet if you change the delay.

## Simulation

Set each testbench as the simulation top in Vivado:

- `tb_clock_generator`
- `tb_i2c_controller`
- `tb_ssm2603_config`

Expected console messages:

- `tb_clock_generator PASS`
- `tb_i2c_controller PASS`
- `tb_ssm2603_config PASS`

The testbenches use accelerated generic clock parameters for practical simulation time. Hardware defaults remain 100 MHz / 100 kHz / 100 ms.

## What this stage does NOT do yet

- It does not receive or transmit audio samples.
- It does not implement I2S.
- It does not implement the equalizer.
- It does not provide audible passthrough yet.

The next stage is `i2s_receiver.vhd` and `i2s_transmitter.vhd`, followed by a passthrough test before adding the biquad filters.

## References

- Digilent Zybo Z7 Reference Manual: https://digilent.com/reference/_media/reference/programmable-logic/zybo-z7/zybo-z7_rm.pdf
- Analog Devices SSM2603 datasheet: https://www.analog.com/media/en/technical-documentation/data-sheets/ssm2603.pdf
- AMD Clocking Wizard guide: https://docs.amd.com/r/en-US/pg065-clk-wiz
- Digilent Zybo Z7 XDC: https://github.com/Digilent/digilent-xdc/blob/master/Zybo-Z7-Master.xdc
