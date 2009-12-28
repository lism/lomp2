--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

local prefix = (...):match("^(.-)[^%.]*$")

local ipairs , require , type , unpack = ipairs , require , type , unpack
local ioopen = io.open

module ( "lomp.fileinfo.flac" , package.see ( lomp ) )

local vstruct = require "vstruct"

require ( prefix .. "vorbiscomments" )
require ( prefix .. "tagfrompath" )
require "modules.albumart"

_NAME = "FLAC reader"

function find ( fd )
	fd:seek ( "set" ) -- Rewind file to start
	if fd:read ( 4 ) == "fLaC" then 
		return fd:seek ( "set" )
	end
end

local blockreaders = {
	[ 0 ] = function ( fd , length , item ) -- STREAMINFO
		local STREAMINFO = vstruct.unpack ( [=[>
			minblocksize:u2 maxblocksize:u2 minframesize:u3 maxframesize:u3
			[ 8 | samplerate:u20 channels:u3 bitspersample:u5 totalsamples:u36 ]
			md5:u16 
		]=] , fd , item.extra )
		item.length = STREAMINFO.totalsamples / STREAMINFO.samplerate
		item.channels = STREAMINFO.channels
		item.samplerate = STREAMINFO.samplerate
		item.bitrate = 	STREAMINFO.samplerate*STREAMINFO.bitspersample
		
	end ,
	[ 1 ] = function ( fd , length , item ) -- PADDING
		local e = item.extra
		e.padding = e.padding or { }
		e.padding [ #e.padding + 1 ] = { start = fd:seek ( ) ; length = length ; }
	end ,
	[ 2 ] = function ( fd , length , item ) -- APPLICATION
		local e = item.extra
		e.applications = e.applications or { }
		e.applications [ #e.applications + 1 ] = vstruct.unpack ( "> appID:u4 appdata:s".. length , fd )
	end ,
	--[[[ 3 ] = function ( fd , length , item ) -- SEEKTABLE (we can't do anything with this)
	end ,--]]
	[ 4 ] = function ( fd , length , item ) -- VORBIS_COMMENT
		item.tagtype = "vorbiscomment"
		item.tags = { }
		item.extra.startvorbis = fd:seek ( "cur" )
		fileinfo.vorbiscomments.info ( fd , item )
	end ,
	[ 5 ] = function ( fd , length , item ) -- CUESHEET
		local e = item.extra
		e.cuesheet = e.cuesheet or { }
		e.cuesheet [ #e.cuesheet + 1 ] = vstruct.unpack ( [=[>
			catalognumber:s128 leadinsamples:u8 [ 1 | cd:b1 x7] x258 tracks:u1
		]=] , fd )
		-- TODO: read CUESHEET_TRACK block
	end ,
	[ 6 ] = function ( fd , length , item ) -- PICTURE
		local e = item.extra
		e.picture = e.picture or { }
		e.picture [ #e.picture + 1 ] = lomp.albumart.processapic ( vstruct.unpack ( [=[>
			type:u4 mimetype:c4 description:c4 width:u4 height:u4 depth:u4 colours:u4 data:c4
		]=] , fd ) )
	end ,
}

function info ( item )
	local fd , err = ioopen ( item.path , "rb" )
	if not fd then return false , "Could not open file:" .. err end
	
	-- Format info found at http://flac.sourceforge.net/format.html
	if fd:read ( 4 ) == "fLaC" then 
		item.format = "flac"
		item.extra = { }
		
		repeat
			local METADATA_BLOCK_HEADER = vstruct.unpack ( "> [ 1 | lastmetadatablock:b1 block_type:u7 ] block_length:u3" , fd )
			local offset = fd:seek ( "cur" )
			local f = blockreaders [ METADATA_BLOCK_HEADER.block_type ] 
			if f then f ( fd , METADATA_BLOCK_HEADER.block_length , item ) end
			fd:seek ( "set" , offset + METADATA_BLOCK_HEADER.block_length )
		until METADATA_BLOCK_HEADER.lastmetadatablock
		
		if not item.tags then
			-- Figure out from path
			item.tagtype = "pathderived"
			item.tags = fileinfo.tagfrompath.info ( path , config.tagpatterns.default )
		end
		
		item.filesize = fd:seek ( "end" )
		
		fd:close ( )
		return item
	else
		-- not a flac file
		fd:close ( )
		return false , "Not a flac file"
	end
end

function edit ( item , edits , inherit )
	local vorbistag = generatetag ( item , edits , inherit )
	local needspace = #vorbistag + 4
	
	local fd , err = ioopen ( item.path , "wb" )
	if not fd then return false , "Could not open file:" .. err end
	
	if fd:read ( 4 ) == "fLaC" then
		local blocks = { }
		repeat
			local startoffset = fd:seek ( "cur" )
			local METADATA_BLOCK_HEADER = vstruct.unpack ( "> [ 1 | lastmetadatablock:b1 block_type:u7 ] block:c3" , fd )
			METADATA_BLOCK_HEADER.startoffset = startoffset
			blocks [ #blocks + 1 ] = METADATA_BLOCK_HEADER
		until METADATA_BLOCK_HEADER.lastmetadatablock
		
		local notspace = { }
		local totalspace = 0
		for i , v in ipairs ( blocks ) do
			if v.block_type == 1 or v.block_type == 4 then -- Padding or Vorbis Comment
				totalspace = totalspace + 4 + #v.block
			else
				notspace [ #notspace + 1 ] = v
			end
		end
		
		-- Move all space to end of headers
		if #blocks ~= #notspace then
			fd:seek ( "set" , 4 )
			for i , v in ipairs ( notspace ) do
				vstruct.pack ( "> [ 1 | x1 block_type:u7 ] block:c3" , fd , v )
			end
		end
		
		-- Ok, now we have all the available space at the end of the metadata section... lets check if we have enough room:
		if totalspace >= needspace and totalspace < ( needspace + 4 ) then -- We fit exactly
			vstruct.pack ( "> [ 1 | lastmetadatablock:b1 block_type:u7 ] block:c3" , fd , { lastmetadatablock = true ; block_type = 4 ; block = vorbistag } )
			fd:seek ( "cur" , totalspace - needspace ) -- Create a bit of illegal padding... can't help it :(
		elseif totalspace >= ( needspace + 4 ) then -- We can fit in...
			vstruct.pack ( "> [ 1 | lastmetadatablock:b1 block_type:u7 ] block:c3" , fd , { lastmetadatablock = false ; block_type = 4 ; block = vorbistag } )
			local paddingminusheader = totalspace - needspace - 4
			vstruct.pack ( "> [ 1 | lastmetadatablock:b1 block_type:u7 ] block_length:u3 x" .. paddingminusheader , fd , { lastmetadatablock = true ; block_type = 1 ; block_length = paddingminusheader } )
		else -- Gonna have to create more room... sigh
			-- TODO
		end
	else
		return false , "Not a flac file"
	end
	fd:close ( )
	
	return
end

return { { "flac" , "fla" } , info , edit }
