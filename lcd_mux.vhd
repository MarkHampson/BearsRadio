library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lcd_mux is
	port(
		clk: in std_logic;
		row1_std: in string (1 to 16);
		row2_std: in string (1 to 16);
		row1: out string (1 to 16);
		row2: out string (1 to 16);
		mute: in std_logic;
		activity: in std_logic
	);
end lcd_mux;

architecture behavioral of lcd_mux is
begin

startup: process(clk)
		constant init_count: integer := 36864000*2;  --2 seconds
		constant no_activity: integer := init_count*15;
		variable count: integer range 0 to no_activity;  -- 30 seconds
		type lcd_state_t is (init, splash, normal, mute);
		variable lcd_state: lcd_state_t;
	begin
		if(rising_edge(clk))then
			case lcd_state is
				when init =>
					if( count = init_count ) then -- switch to standard input
						lcd_state := normal;
						count := 0; --reset count
					else
						count := count + 1;
						row1 <= "     BEARS      ";
						row2 <= "     Radio      ";
					end if;
				when normal =>
					row1 <= row1_std;
					row2 <= row2_std;
					if(count = no_activity) then
						lcd_state := splash;
					elsif(activity = '1') then --reset count
						count := 0;
					elsif(mute = '1') then
						lcd_state := mute;
					else
						count := count + 1;
					end if;
				when splash =>
					row1 <= "     BEARS      ";
					row2 <= "     Radio      ";
					if(activity = '1') then
						lcd_state := normal;
						count := 0;
					elsif(mute = '1') then
						lcd_state := mute;
					end if;
				when mute =>
					row1 <= "      MUTE      ";
					row2 <= "                ";
					if(mute = '0' or activity = '1') then
						lcd_state := normal;
						count := 0;
					end if;
			end case;
		end if;
	end process;

end behavioral;
