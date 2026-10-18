### Configuring the FPGA RTG raster

Edit the `RTG_*` constants at the start of the architecture in
[`minimig_icepi-zero_top.vhd`](rtl/soc/minimig_icepi-zero_top.vhd) or
[`minimig_fleaohm_top.vhd`](rtl/soc/minimig_fleaohm_top.vhd).
`RTG_PIXELX5_HZ` derives from `5 * RTG_PIXEL_HZ`; both feed the auxiliary PLL,
and HDMI uses the same pixel frequency. Active dimensions also reach the RTG
DMA/scanout module. Totals, sync timing, polarity and CEA mode feed HDMI.
Sync pulse starts are front porches after active video; polarity bit 0 inverts
HSync and bit 1 inverts VSync. CEA mode 0 leaves the video code unspecified.
The RTG preparation delay remains 4096 `clk_sys` cycles.

Choose the matching driver profile and update SDC/LPF clock constraints when
changing the raster or clock. These build-time constants do not reprogram
video timing at runtime.
