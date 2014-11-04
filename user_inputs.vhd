library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity user_inputs is
	port(
		clk: in std_logic;
		button_increase: in std_logic;
		button_decrease: in std_logic;
		button_mode: in std_logic;
		RF_payload: in std_logic_vector(15 downto 0);
		payload_ready: in std_logic;
		
		increase: out std_logic;
		decrease: out std_logic;
		increment_ack: in std_logic;
		address_increment: out std_logic_vector(16 downto 0);
		
		mode_string: out string(1 to 16);
		mute: buffer std_logic;
		activity: out std_logic
		
	);
end user_inputs;

architecture Roman of user_inputs is

	signal synch_increase1, synch_increase2, synch_decrease1, synch_decrease2,
		   synch_mode1, synch_mode2: std_logic;
		   
	type button_state_t is (released, pressed);
	type output_state_t is (idle, output_increase, output_decrease);
	
	signal increase_state: button_state_t;
	signal decrease_state: button_state_t;
	signal mode_state: button_state_t;
	signal output_state: output_state_t;
	
	signal payload_ready_trigger: std_logic;
	signal payload_ready_history: std_logic_vector(1 downto 0);
	
	constant sample_stride: integer := 2; -- left and right channel
	constant sample_rate: integer := 48000;
	constant delay_1sec: integer := sample_rate * sample_stride;
	constant delay_100ms: integer := delay_1sec/10;
	constant delay_25ms: integer := delay_100ms/4;
	constant delay_10ms: integer := delay_100ms/10;
	constant delay_1ms: integer := delay_10ms/10;
	constant num_words16: integer := 2**22; -- number of 16 bit words in SDRAM
	constant delay_large: integer := delay_1sec;
	constant delay_small: integer := delay_25ms;
	signal current_mode: integer range 0 to 4;
	signal sample_delay: integer range 0 to num_words16;
	type delay_mode_t is array (0 to 4) of integer range 0 to delay_1sec;
	signal delay_mode: delay_mode_t := (delay_1sec, delay_100ms, delay_25ms, delay_10ms, delay_1ms);
	
	signal press_increase, press_decrease, press_mode: boolean;
	signal RF_toggle, RF_increase_large, RF_increase_small,
			RF_decrease_large, RF_decrease_small: boolean;

begin

synchronize_buttons: process(clk)
	begin
		if(clk'event and clk = '1') then
			synch_increase1 <= button_increase;
			synch_increase2 <= synch_increase1;
			synch_decrease1 <= button_decrease;
			synch_decrease2 <= synch_decrease1;
			synch_mode1 <= button_mode;
			synch_mode2 <= synch_mode1;
		end if;
	end process;
	
payload_rdy_history: process(clk)
	begin
		if(clk'event and clk = '1') then
			payload_ready_history(0) <= payload_ready;
			payload_ready_history(1) <= payload_ready_history(0);
		end if;
	end process;

detect_new_payload: process(clk)
	begin
		if(clk'event and clk = '1') then
			if( payload_ready_history = "01" ) then
				payload_ready_trigger <= '1';
			else
				payload_ready_trigger <= '0';
			end if;
		end if;
	end process;
	
button_debouncer_increase: process(clk)
        constant timer_count_high: integer := 2**17-1;
		variable timer_count: integer range 0 to timer_count_high; -- about 3.5 ms at 36.864 MHz
	begin
		if(clk'event and clk = '1') then
			case increase_state is
				when released =>
					if( synch_increase2 = '1' ) then -- press detected
						if( timer_count = timer_count_high) then -- button has been deemed pressed
							increase_state <= pressed;
							press_increase <= true;
							timer_count := 0; -- reset count
						else
							timer_count := timer_count + 1;
						end if;
					else
						press_increase <= false;
						timer_count := 0; -- reset count
					end if;
				when pressed =>
					press_increase <= false;
					if( synch_increase2 = '0' ) then -- release detected
						if( timer_count = timer_count_high) then
							increase_state <= released;
							timer_count := 0;
						else
							timer_count := timer_count + 1;
						end if;
					else
						timer_count := 0;
					end if;
			end case;
		end if;
	end process;

button_debouncer_decrease: process(clk)
        constant timer_count_high: integer := 2**17-1;
		variable timer_count: integer range 0 to timer_count_high; -- about 3.5 ms at 36.864 MHz
	begin
		if(clk'event and clk = '1') then
			case decrease_state is
				when released =>
					if( synch_decrease2 = '1' ) then -- press detected
						if( timer_count = timer_count_high) then -- button has been deemed pressed
							decrease_state <= pressed;
							press_decrease <= true;
							timer_count := 0; -- reset count
						else
							timer_count := timer_count + 1;
						end if;
					else
						press_decrease <= false;
						timer_count := 0; -- reset count
					end if;
				when pressed =>
					press_decrease <= false;
					if( synch_decrease2 = '0' ) then -- release detected
						if( timer_count = timer_count_high) then
							decrease_state <= released;
							timer_count := 0;
						else
							timer_count := timer_count + 1;
						end if;
					else
						timer_count := 0;
					end if;
			end case;
		end if;
	end process;	
	
button_debouncer_mode: process(clk)
        constant timer_count_high: integer := 2**17-1;
		variable timer_count: integer range 0 to timer_count_high; -- about 3.5 ms at 36.864 MHz
	begin
		if(clk'event and clk = '1') then
			case mode_state is
				when released =>
					if( synch_mode2 = '1' ) then -- press detected
						if( timer_count = timer_count_high) then -- button has been deemed pressed
							mode_state <= pressed;
							press_mode <= true;
							timer_count := 0; -- reset count
						else
							timer_count := timer_count + 1;
						end if;
					else
						press_mode <= false;
						timer_count := 0; -- reset count
					end if;
				when pressed =>
					press_mode <= false;
					if( synch_mode2 = '0' ) then -- release detected
						if( timer_count = timer_count_high) then
							mode_state <= released;
							timer_count := 0;
						else
							timer_count := timer_count + 1;
						end if;
					else
						timer_count := 0;
					end if;
			end case;
		end if;
	end process;	
	
RF_payload_parser: process(clk)
		constant up: std_logic_vector(7 downto 0) := X"1D";
		constant down: std_logic_vector(7 downto 0) := X"1E";
		constant left: std_logic_vector(7 downto 0) := X"17";
		constant right: std_logic_vector(7 downto 0) := X"1B";
		constant middle: std_logic_vector(7 downto 0) := X"0F";
	begin
		if(clk'event and clk = '1') then
			if(payload_ready_trigger = '1') then 
				case RF_payload(7 downto 0) is
					when up =>
						RF_increase_large <= true;
					when down =>
						RF_decrease_large <= true;
					when left =>
						RF_decrease_small <= true;
					when right =>
						RF_increase_small <= true;
					when middle =>
						RF_toggle <= true;
					when others =>
				end case;
			else
				RF_increase_large <= false;
				RF_increase_small <= false;
				RF_decrease_large <= false;
				RF_decrease_small <= false;
				RF_toggle <= false;
			end if;
		end if;
	end process;
	
mode_update: process(clk)
	begin
		if(clk'event and clk = '1') then
			if(press_mode) then
				if(current_mode = 4) then
					current_mode <= 0;
				else current_mode <= current_mode + 1;
				end if;
			end if;
		end if;
	end process;

process(current_mode)
begin
	case current_mode is
		when 0 =>
			mode_string <= "Delay Step: 1sec";
		when 1 =>
			mode_string <= "Delay Step:100ms";
		when 2 =>
			mode_string <= "Delay Step: 25ms";
		when 3 =>
			mode_string <= "Delay Step: 10ms";
		when 4 =>
		    mode_string <= "Delay Step:  1ms";
	end case;
end process;	
	
outputs: process(clk)
		begin
			if(clk'event and clk = '1') then
				case output_state is
					when idle =>
						if(RF_increase_large or RF_increase_small or press_increase) then
							output_state <= output_increase;
							activity <= '1';
							mute <= '0';
							if(press_increase) then
								address_increment <= std_logic_vector(to_unsigned(delay_mode(current_mode), 17));
							elsif(RF_increase_large) then
								address_increment <= std_logic_vector(to_unsigned(delay_large, 17));
							elsif(RF_increase_small) then
								address_increment <= std_logic_vector(to_unsigned(delay_small, 17));
							end if;
						elsif(RF_decrease_large or RF_decrease_small or press_decrease) then
							output_state <= output_decrease;
							activity <= '1';
							mute <= '0';
							if(press_decrease) then
								address_increment <= std_logic_vector(to_unsigned(delay_mode(current_mode), 17));
							elsif(RF_decrease_large) then
								address_increment <= std_logic_vector(to_unsigned(delay_large, 17));
							elsif(RF_decrease_small) then
								address_increment <= std_logic_vector(to_unsigned(delay_small, 17));
							end if;
						elsif(RF_toggle) then
							mute <= mute xor '1';
							activity <= '0';
						elsif(press_mode) then
						    activity <= '1';
						    mute <= '0';
						else
							activity <= '0';
						end if;
					when output_increase =>
						increase <= '1';
						if( increment_ack = '1' ) then
							increase <= '0';
							output_state <= idle;
						end if;
					when output_decrease =>
						decrease <= '1';
						if( increment_ack = '1' ) then
							decrease <= '0';
							output_state <= idle;
						end if;
				end case;
			end if;
		end process;


end Roman;