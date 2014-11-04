library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sdram_controller;
use work.i2s_comm;
use work.i2c_comm;
use work.audio_manager;
use work.lcd_controller;
use work.user_inputs;
use work.nordic;
use work.lcd_mux;

entity radio_delay is
	port(
		clkin: in std_logic;
		
--		ledr0: out std_logic;
		led0: out std_logic;
		led1: out std_logic;
		led2: out std_logic;
--		
		--delay pins
		increase: in std_logic;
		decrease: in std_logic;
		mode: in std_logic;
		
		-- I2C pins
		sda: inout std_logic;
		scl: out std_logic;
		
		-- I2S pins
		mclk: out std_logic;
		bclk: out std_logic;
		tx_lrclk: buffer std_logic;
		rx_lrclk: buffer std_logic;
		tx_data: out std_logic;
		rx_data: in std_logic;
		
		-- SDRAM pins
		sdram_clk: out std_logic;
		cke: out std_logic; -- clock enable
		n_cs: buffer std_logic; -- chip select
		n_ras: buffer std_logic; -- row address strobe
		n_cas: buffer std_logic; -- column address strobe
		n_we: buffer std_logic; -- write enable
		dq: inout std_logic_vector(15 downto 0);
		dqm: out std_logic; -- DQ mask enable
		ldqm: out std_logic;
		addr: buffer std_logic_vector(11 downto 0);
		ba: out std_logic_vector(1 downto 0);
		
		-- LCD pins
		backlight: out std_logic;
		--lcd_on: out std_logic;
		lcd_rs: out std_logic;
		lcd_rw: out std_logic;
		lcd_e: out std_logic;
		lcd_data: out std_logic_vector( 7 downto 0);
		
		-- Nordic transceiver pins
		irq: in std_logic;
		mosi: out std_logic;
		miso: in std_logic;
		sck: out std_logic;
		csn: out std_logic;
		ce: out std_logic
		
	);
end radio_delay;

architecture Merovingian of radio_delay is
	
	signal done: std_logic;
	
	signal i2s_data_received: std_logic_vector(47 downto 0);
	signal i2s_data_send: std_logic_vector(47 downto 0);
	
	signal write_to_ram: std_logic_vector(15 downto 0);
	signal read_from_ram: std_logic_vector(15 downto 0);
	signal ram_address:std_logic_vector(21 downto 0);
	signal ram_enable: boolean;
	signal ack: boolean;
	signal read_nwrite: boolean;
	signal test: boolean;
	
	signal delay_inc: std_logic;
	signal delay_dec: std_logic;
	signal delay_mode: std_logic;
	
	signal increase_strobe: std_logic;
	signal decrease_strobe: std_logic;
	
	signal row1,row2,row1_std,row2_std: string(1 to 16);
	
	signal payload: std_logic_vector(15 downto 0);
	signal payload_ready: std_logic;
	
	signal increment_ack: std_logic;
	signal address_increment: std_logic_vector(16 downto 0);
	signal clk, clkout2: std_logic;
	
	signal mute, activity: std_logic;

--constant i2s_data_send: Std_logic_vector(47 downto 0) := X"123456654321";

    component clk_wiz_v3_6_0
    port
     (-- Clock in ports
      CLK_IN1           : in     std_logic;
      -- Clock out ports
      CLK_OUT1          : out    std_logic;
      CLK_OUT2          : out std_logic
     );
    end component;
	
begin
--
led1 <= done;
led2 <= payload_ready;

delay_inc <= not increase;
delay_dec <= not decrease;
delay_mode <= not mode;

--ledr17 <= std_logic'val(std_logic'pos('0') + boolean'pos(test));

--pll_module: component pll
--	port map(
--			inclk0 => clk,
--			c0 => mclk,
--			locked => ledr0
--			);

pll_clk : clk_wiz_v3_6_0
  port map
   (-- Clock in ports
    CLK_IN1 => clkin,
    -- Clock out ports
    CLK_OUT1 => clk,
    CLK_OUT2 => clkout2);

mclk <= clkout2;  	--12.288 MHz

i2s_module: entity i2s_comm
	port map(
		clk => clk,
		enable => done,
		bclk => bclk,
		tx_data => tx_data,
		tx_lrclk => tx_lrclk,
		rx_data => rx_data,
		rx_lrclk => rx_lrclk,
		data_to_send => i2s_data_send,
		data_received => i2s_data_received
	);
	
i2c_module: entity i2c_comm
	port map(
		clk => clk,
		sda => sda,
		scl => scl,
		ack => led0,
		done => done
		);

sdram: entity sdram_controller port map(
	clk => clk,	
	-- SDRAM control pins
	sdram_clk => sdram_clk,
	cke => cke,
	n_cs => n_cs,
	n_ras => n_ras,
	n_cas => n_cas,
	n_we => n_we,
	dq => dq,
	dqm => dqm,
	ldqm => ldqm,
	addr => addr,
	ba => ba,
	-- User interface
	data_received => read_from_ram,
	send_this_data => write_to_ram,
	address => ram_address,
	enable => ram_enable,
	ack => ack,
	read_data_valid => open,
	read_nwrite => read_nwrite
	);

manager: entity audio_manager port map(
	clk => clk,
	test => test,
	increase_delay => increase_strobe,
	decrease_delay => decrease_strobe,
	increment_ack => increment_ack,
	address_increment => address_increment,
	delay_string => row2_std,
	-- interface to I2S module
	lrclk => tx_lrclk, -- doesn't matter if this is rx or tx lrclk
	i2s_data_received => i2s_data_received,
	i2s_data_send => i2s_data_send,
	-- interface to SDRAM controller module
	write_to_ram => write_to_ram,
	read_from_ram => read_from_ram,
	ram_address => ram_address,
	ram_enable => ram_enable,
	ack => ack,
	mute => mute,
	read_nwrite => read_nwrite
	);

user_interface: entity user_inputs port map(
		clk => clk,
		button_increase => delay_inc,
		button_decrease => delay_dec,
		button_mode => delay_mode,
		RF_payload => payload,
		payload_ready => payload_ready,
		increase => increase_strobe,
		decrease => decrease_strobe,
		increment_ack => increment_ack,
		address_increment => address_increment,
		mode_string => row1_std,
		mute => mute,
		activity => activity
		);

wireless_module: entity nordic port map(
		clk => clk,
		irq => irq,
		mosi => mosi,
		miso => miso, 
		sck => sck, 
		csn => csn,
		ce => ce,
		payload_ready => payload_ready,
		button => payload -- this is actually the RF payload
		);

lcd_selector:
	entity lcd_mux
	port map(
		clk => clk,
		row1_std => row1_std,
		row2_std => row2_std,
		row1 => row1,
		row2 => row2,
		mute => mute,
		activity => activity
		);
		
lcdcontroller: 
	entity lcd_controller
	port map(
		clk => clk,
		row1_text => row1,
		row2_text => row2,
		backlight => backlight,
		--lcd_on => lcd_on,
		lcd_rs => lcd_rs,
		lcd_rw => lcd_rw,
		lcd_e => lcd_e,
		lcd_data => lcd_data
		);	
	

end Merovingian;