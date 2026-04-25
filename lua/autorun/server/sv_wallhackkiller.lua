--[[

          _______  _        _                       _______  _______  _              _       _________ _        _        _______  _______ 
|\     /|(  ___  )( \      ( \            |\     /|(  ___  )(  ____ \| \    /\      | \    /\\__   __/( \      ( \      (  ____ \(  ____ )
| )   ( || (   ) || (      | (            | )   ( || (   ) || (    \/|  \  / /      |  \  / /   ) (   | (      | (      | (    \/| (    )|
| | _ | || (___) || |      | |            | (___) || (___) || |      |  (_/ /       |  (_/ /    | |   | |      | |      | (__    | (____)|
| |( )| ||  ___  || |      | |            |  ___  ||  ___  || |      |   _ (        |   _ (     | |   | |      | |      |  __)   |     __)
| || || || (   ) || |      | |            | (   ) || (   ) || |      |  ( \ \       |  ( \ \    | |   | |      | |      | (      | (\ (   
| () () || )   ( || (____/\| (____/\      | )   ( || )   ( || (____/\|  /  \ \      |  /  \ \___) (___| (____/\| (____/\| (____/\| ) \ \__
(_______)|/     \|(_______/(_______/      |/     \||/     \|(_______/|_/    \/      |_/    \/\_______/(_______/(_______/(_______/|/   \__/
        
                   _                       
                  | |                      
  _ __  _   ___  _| |_ ___  __ _ _ __ ___  
 | '_ \| | | \ \/ / __/ _ \/ _` | '_ ` _ \ 
 | | | | |_| |>  <| ||  __/ (_| | | | | | |
 |_| |_|\__, /_/\_\\__\___|\__,_|_| |_| |_|
         __/ |                             
        |___/                              


By MaryBlackfild and kristov6

Hi!

This is an experimental version of WallHackKiller, and we assume no responsibility for its use during this testing phase.
However, we welcome any feedback or reports of bugs and errors, and we can help you configure it for your server.
Follow us on Telegram and Discord to get guaranteed support.

Join to our Telegram for support: t.me/nyxteam_gmod
Join to our Discord for support: discord.gg/rUEEz4mfXw

--]]

if not SERVER then return end
WallHackKiller = WallHackKiller or {}
include("autorun/server/sv_wallhackkiller_bypass.lua")
include("autorun/server/sv_wallhackkiller_core.lua")
