----------------------------------------------------------------------------------
-- "Environment 1" (aka env1) is inspired by the classic QNICE/A evaluation
-- board environment. Features:
--
--    * the original layout: lower 32kB are ROM, upper 32kB are RAM
--    * memory mapped IO beginning at 0xFF00
--    * 4 TIL-311 displays at 0xFF10: 0xFF10 is the value to be displayed
--                                    0xFF11 lower 4 bit are a display bit mask
-- 
-- done in 2015 by sy2002
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use work.env1_globals.all;

entity env1 is
port (
   CLK         : in std_logic;                      -- 100 MHz clock
   RESET_N     : in std_logic;                      -- CPU reset button (negative, i.e. 0 = reset)
   
   -- 7 segment display: common anode and cathode
   SSEG_AN     : out std_logic_vector(7 downto 0);  -- common anode: selects digit
   SSEG_CA     : out std_logic_vector(7 downto 0)   -- cathode: selects segment within a digit   
); 
end env1;

architecture beh of env1 is

-- QNICE CPU
component QNICE_CPU
port (
   -- clock
   CLK            : in std_logic;
   RESET          : in std_logic;
   
   WAIT_FOR_DATA  : in std_logic;                            -- 1=CPU adds wait cycles while re-reading from bus
      
   ADDR           : out std_logic_vector(15 downto 0);      -- 16 bit address bus
   
   --tristate 16 bit data bus
   DATA           : inout std_logic_vector(15 downto 0);    -- send/receive data
   DATA_DIR       : out std_logic;                          -- 1=DATA is sending, 0=DATA is receiving
   DATA_VALID     : out std_logic                           -- while DATA_DIR = 1: DATA contains valid data   
);
end component;

-- ROM
component ROM_FROM_FILE is
generic (
   ADDR_WIDTH : integer range 2 to 64;    -- address width
   DATA_WIDTH : integer range 2 to 64;    -- word width of ROM output port (aka DATA)
   SIZE       : integer;                  -- amount of words (aka lines in input file)
   FILE_NAME  : string                    -- name of input file; input file format:
                                          -- DATA_WIDTH bits, written as 0 and 1 in each line
);
port (
   en    : in std_logic;                                 -- new values only if enable is 1
   addr  : in std_logic_vector(ADDR_WIDTH - 1 downto 0); -- address
   data  : out std_logic_vector(DATA_WIDTH - 1 downto 0) -- data located at address
);
end component;

-- BLOCK RAM
component BRAM is
port (
   clk      : in std_logic;                        -- read and write on rising clock edge
   ce       : in std_logic;                        -- chip enable, when low then high impedance
   
   address  : in std_logic_vector(15 downto 0);    -- address is for now 16 bit hard coded
   we       : in std_logic;                        -- write enable
   data_i   : in std_logic_vector(15 downto 0);    -- write data
   data_o   : out std_logic_vector(15 downto 0);   -- read data
   
   busy     : out std_logic                        -- 1=still executing, i.e. can drive CPU's WAIT_FOR_DATA   
);
end component;

-- Nexys 4 DDR specific 7 segment display driver
component drive_7digits
generic (
   CLOCK_DIVIDER        : integer                  -- clock divider: clock cycles per digit cycle
);
port (
   clk    : in std_logic;                          -- clock signal divided by above mentioned divider
   
   digits : in std_logic_vector(31 downto 0);      -- the actual information to be shown on the display
   mask   : in std_logic_vector(7 downto 0);       -- control individual digits ('1' = digit is lit)  
   
   -- 7 segment display needs multiplexed approach due to common anode
   SSEG_AN     : out std_logic_vector(7 downto 0); -- common anode: selects digit
   SSEG_CA     : out std_logic_vector(7 downto 0) -- cathode: selects segment within a digit 
);
end component;

-- multiplexer to control the data bus (enable/disable the different parties)
component mmio_mux is
port (
   -- input from CPU
   addr              : in std_logic_vector(15 downto 0);
   data_dir          : in std_logic;
   data_valid        : in std_logic;
   
   -- let the CPU wait for data from the bus
   cpu_wait_for_data : out std_logic;   
   
   -- ROM is enabled when the address is < $8000 and the CPU is reading
   rom_enable        : out std_logic;
   ram_enable        : out std_logic;
   ram_busy          : in std_logic;   
   til_reg0_enable   : out std_logic;
   til_reg1_enable   : out std_logic   
);
end component;

signal cpu_addr               : std_logic_vector(15 downto 0);
signal cpu_data               : std_logic_vector(15 downto 0);
signal cpu_data_dir           : std_logic;
signal cpu_data_valid         : std_logic;
signal cpu_wait_for_data      : std_logic;

signal TIL_311_buffer         : std_logic_vector(15 downto 0) := x"0000";
signal TIL_311_mask           : std_logic_vector(3 downto 0)  := "1111";

-- MMIO control signals
signal rom_enable             : std_logic;
signal ram_enable             : std_logic;
signal ram_busy               : std_logic;
signal til_reg0_enable        : std_logic;
signal til_reg1_enable        : std_logic;

begin

   -- QNICE CPU
   cpu : QNICE_CPU
      port map
      (
         CLK => CLK,
         RESET => not RESET_N,
         WAIT_FOR_DATA => cpu_wait_for_data,
         ADDR => cpu_addr,
         DATA => cpu_data,
         DATA_DIR => cpu_data_dir,
         DATA_VALID => cpu_data_valid
      );

   -- ROM: up to 64kB consisting of up to 32.000 16 bit words
   rom : ROM_FROM_FILE
      generic map
      (
         ADDR_WIDTH => 16,
         DATA_WIDTH => 16,
         SIZE       => ROM_SIZE,
         FILE_NAME  => ROM_FILE                                      
      )
      port map(
         en => rom_enable, -- enable ROM if lower 32k word and CPU in read mode
         addr => "0" & cpu_addr(14 downto 0),
         data => cpu_data
      );
     
   -- RAM: up to 64kB consisting of up to 32.000 16 bit words
   ram : BRAM
      port map (
         clk => CLK,
         ce => ram_enable,
         address => "0" & cpu_addr(14 downto 0),
         we => cpu_data_dir,         
         data_i => cpu_data,
         data_o => cpu_data,
         busy => ram_busy         
      );
        
   -- 7 segment display
   disp_7seg : drive_7digits
      generic map
      (
         CLOCK_DIVIDER => 200000 -- 200.000 clock cycles @ 100 MHz = 2ms per digit
      )
      port map
      (
         clk => CLK,
         digits => x"0000" & TIL_311_buffer,
         mask => "0000" & TIL_311_mask,
         SSEG_AN => SSEG_AN,
         SSEG_CA => SSEG_CA
      );      
      
   -- memory mapped i/o controller
   mmio_controller : mmio_mux
      port map
      (
         addr => cpu_addr,
         data_dir => cpu_data_dir,
         data_valid => cpu_data_valid,
         cpu_wait_for_data => cpu_wait_for_data,
         rom_enable => rom_enable,
         ram_enable => ram_enable,
         ram_busy => ram_busy,
         til_reg0_enable => til_reg0_enable,
         til_reg1_enable => til_reg1_enable
      );
      
   -- clock-in the current to-be-displayed value and mask into a FF for the TIL
   til_driver : process(CLK)
   begin
      if falling_edge(CLK) then
         if til_reg0_enable = '1' then
            TIL_311_buffer <= cpu_data;            
         end if;
         
         if til_reg1_enable = '1' then
            TIL_311_mask <= cpu_data(3 downto 0);
         end if;
      end if;
   end process;
   
end beh;

