-- 80x40 Textmode VGA
-- meant to be connected with the QNICE CPU as data I/O controled through MMIO
-- tristate outputs go high impedance when not enabled
-- done by sy2002 in December 2015

-- this is mainly a wrapper around Javier Valcarce's component
-- http://www.javiervalcarce.eu/wiki/VHDL_Macro:_VGA80x40

-- how to make fonts, see http://nafe.sourceforge.net/
-- then use the psf2coe.rb and then coe2rom.pl toolchain to generate .rom files

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_textmode is
port (
   reset    : in std_logic;     -- async reset
   clk50MHz : in std_logic;     -- needs to be a 50 MHz clock

   -- VGA registers
   en       : in std_logic;     -- enable for reading from or writing to the bus
   we       : in std_logic;     -- write to VGA's registers via system's data bus
   reg      : in std_logic_vector(3 downto 0);     -- register selector
   data     : inout std_logic_vector(15 downto 0); -- system's data bus
   
   -- VGA output signals, monochrome only
   R        : out std_logic;
   G        : out std_logic;
   B        : out std_logic;
   hsync    : out std_logic;
   vsync    : out std_logic
);
end vga_textmode;

architecture beh of vga_textmode is

component vga80x40
port (
   reset       : in  std_logic;
   clk25MHz    : in  std_logic;

   -- VGA signals, monochrome only   
   R           : out std_logic;
   G           : out std_logic;
   B           : out std_logic;
   hsync       : out std_logic;
   vsync       : out std_logic;
   
   -- address and data lines of video ram for text
   TEXT_A           : out std_logic_vector(11 downto 0);
   TEXT_D           : in  std_logic_vector(07 downto 0);
   
   -- address and data lines of font rom
   FONT_A           : out std_logic_vector(11 downto 0);
   FONT_D           : in  std_logic_vector(07 downto 0);
   
   -- hardware cursor x and y positions
   ocrx    : in  std_logic_vector(7 downto 0);
   ocry    : in  std_logic_vector(7 downto 0);
   
   -- control register
   -- Bit 7 VGA enable signal
   -- Bit 6 HW cursor enable bit
   -- Bit 5 is Blink HW cursor enable bit
   -- Bit 4 is HW cursor mode (0 = big; 1 = small)
   -- Bits(2:0) is the output color.
   octl    : in  std_logic_vector(7 downto 0)
);   
end component;

component video_bram
generic (
   SIZE_BYTES     : integer;    -- size of the RAM/ROM in bytes
   CONTENT_FILE   : string;     -- if not empty then a prefilled RAM ("ROM") from a .rom file is generated
   FILE_LINES     : integer;    -- size of the content file in lines (files may be smaller than the RAM/ROM size)   
   DEFAULT_VALUE  : bit_vector  -- default value to fill the memory with
);
port (
   clk            : in std_logic;
   we             : in std_logic;   
   address_i      : in std_logic_vector(15 downto 0);
   address_o      : in std_logic_vector(15 downto 0);
   data_i         : in std_logic_vector(7 downto 0);
   data_o         : out std_logic_vector(7 downto 0)
);
end component;

signal clk25MHz   : std_logic;

-- signals for wiring video and font ram with the vga80x40 component
signal vga_text_a : std_logic_vector(11 downto 0);
signal vga_text_d : std_logic_vector(7 downto 0);
signal vga_font_a : std_logic_vector(11 downto 0);
signal vga_font_d : std_logic_vector(7 downto 0);

-- signals for write-accessing the video ram
signal vmem_addr  : std_logic_vector(11 downto 0);
signal vmem_data  : std_logic_vector(7 downto 0);
signal vmem_we    : std_logic;

-- VGA control signals
signal vga_x      : std_logic_vector(7 downto 0) := x"00";
signal vga_y      : std_logic_vector(6 downto 0) := "0000000";
signal vga_ctl    : std_logic_vector(7 downto 0) := "00000000";
signal vga_char   : std_logic_vector(7 downto 0) := x"00";

-- operation
type cmd_type is (c_idle, c_start, c_store);
signal cmd_store_en : std_logic := '0';
signal cmd_store  : cmd_type := c_idle;

begin

   vga : vga80x40
      port map (
         reset => reset,
         clk25MHz => clk25MHz,
         R => R,
         G => G,
         B => B,
         hsync => hsync,
         vsync => vsync,
         TEXT_A => vga_text_a,
         TEXT_D => vga_text_d,
         FONT_A => vga_font_a,
         FONT_D => vga_font_d,
         ocrx => vga_x,
         ocry => "0" & vga_y,
         octl => vga_ctl
      );

   video_ram : video_bram
      generic map (
         SIZE_BYTES => 3200,                             -- 80 columns x 40 lines = 3.200 bytes
         CONTENT_FILE => "testscreen.rom",               -- @TODO remove test image -- don't specify a file, so this is RAM
         FILE_LINES => 120,
         DEFAULT_VALUE => x"20"                          -- ACSII code of the space character
      )
      port map (
         clk => clk25MHz,
         we => vmem_we,
         address_o => "0000" & vga_text_a,
         data_o => vga_text_d,
         address_i => "0000" & vmem_addr,
         data_i => vmem_data
      );
      
   font_rom : video_bram
      generic map (
         SIZE_BYTES => 3072,
         CONTENT_FILE => "lat0-12.rom",
         FILE_LINES => 3072,
         DEFAULT_VALUE => x"00"
      )
      port map (
         clk => clk25MHz,
         we => '0',
         address_o => "0000" & vga_font_a,
         data_o => vga_font_d,
         address_i => (others => '0'),
         data_i => vmem_data -- will be ignored since we is '0'
      );
      
   manage_cmd_store : process (cmd_store_en, cmd_store, clk25MHz, vga_char, vga_x, vga_y)
   variable tmp : IEEE.NUMERIC_STD.unsigned(13 downto 0);
   variable tsl : std_logic_vector(13 downto 0);
   begin
      vmem_we <= '0';
      vmem_addr <= (others => '0');
      vmem_data <= vga_char;
      
      if cmd_store_en ='1' or cmd_store = c_start or cmd_store = c_store then
         vmem_we <= '1';
         tmp := IEEE.NUMERIC_STD.unsigned(vga_x) + (IEEE.NUMERIC_STD.unsigned(vga_y) * 80);
         tsl := std_logic_vector(tmp);
         vmem_addr <= tsl(11 downto 0);
         
         if cmd_store_en = '1' then
            cmd_store <= c_start;
         end if;
         
         if rising_edge(clk25MHz) then
            if cmd_store = c_start then
               cmd_store <= c_store;
            elsif cmd_store = c_store then
               cmd_store <= c_idle;
            end if;
         end if;
      end if;      
   end process;
   
   manage_registers : process (en, we, reg, data)
   begin
      data <= (others => 'Z');
      cmd_store_en <= '0';

      if rising_edge(en) then
         if we = '1' and reg = x"0" then
            vga_ctl <= data(7 downto 0);
         end if;
      end if;
      
      if rising_edge(en) then
         if we = '1' and reg = x"1" then
            vga_x <= data(7 downto 0);
         end if;
      end if;
      
      if rising_edge(en) then
         if we = '1' and reg = x"2" then
            vga_y <= data(6 downto 0);
         end if;
      end if;
      
      if rising_edge(en) then
         if we = '1' and reg = x"3" then
            vga_char <= data(7 downto 0);
         end if;
      end if;
      
      if en = '1' and we = '1' and reg = x"3" then
         cmd_store_en <= '1';
      end if;
   end process;         

   clk25MHz <= '0' when reset = '1' else
               not clk25MHz when rising_edge(clk50MHz);
end beh;
