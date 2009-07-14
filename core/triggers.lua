--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.triggers" , package.see ( lomp ) )

local callbacks = {
	playlist_create = { function ( num , pl ) updatelog ( "Created playlist #" .. num .. ": '" .. pl.name .. "'" , 4 ) end } ;
	playlist_delete = { function ( num , pl ) updatelog ( "Deleted playlist #" .. num .. " (" .. pl.name .. ")" , 4 ) end } ;
	playlist_clear = { function ( num , pl ) updatelog ( "Cleared playlist #" .. num .. " (" .. pl.name .. ")" , 4 ) end } ;
	playlist_sort = { function ( num , pl ) updatelog ( "Sorted playlist #" .. num .. " (" .. pl.name .. ")" , 4 ) end } ;
	
	item_add = { function ( num , pl , position , object ) updatelog ( "Added item to playlist #" .. num .. " (" .. pl.name .. ") position #" .. position .. " Source: " .. object.source  , 4 ) end } ;
	item_remove = { function ( num , pl , position , object ) updatelog ( "Removed item from playlist #" .. num .. " (" .. pl.name .. ") position #" .. position .. " Source: " .. object.source  , 4 ) end } ;
	
	playback_stop = { } ; -- ( typ , source , stopoffset )
	playback_pause = { } ;--  ( )
	playback_unpause = { } ; -- ( )
	playback_startsong = { } ; -- ( typ , source ) -- Triggered when song is played
	
	player_abouttofinish = { } ; -- ( )
	player_finished = { } ; -- ( typ , source )
}

function registercallback ( callback , func , name )
	local pos = #callbacks [ callback ] + 1
	callbacks [ callback ] [ pos ] = func
	callbacks [ callback ] [ name ] = pos
	return pos
end
function deregistercallback ( callback , name )
	table.remove ( callbacks [ callback ] , callbacks [ callback ] [ name ] )
	callbacks [ callback ] [ name ] = nil
end
function triggercallback ( callback , ... )
	for i , v in ipairs ( callbacks [ callback ] ) do v ( ... ) end
end

registercallback ( "playback_startsong" , function ( )
		vars.queue [ 0 ].played = true -- Better way to figure this out?
	end , "Set Played" )
