---------------------------------------------
--Versions
---------------------------------------------
--1.0 - basic folder walk
--1.0.1 - Modified to upload .jpg only and go from most recent filename 03/01/18

require("Settings")

local blackList = {}
local dateTable = {}
local parseThreads = 0
local ftpstring = "ftp://"..user..":"..passwd.."@"..server.."/"..serverDir.."/"
local lockdir = "/uploaded/"   -- trailing slash required, and folder must already exist

local fileTable = {}

--Options
local sortByFileName = false -- If true sorts alphabetically by file else sorts by modified date
local jpegsOnly = true --Excludes .RAW files if set to true


local function exists(path)
    if lfs.attributes(path) then
        return true
    else
        return false
    end
end

local function is_uploaded(path)
    local hash = fa.hash("md5", path, "")
    return exists(lockdir .. hash)
end

local function set_uploaded(path)
    local hash = fa.hash("md5", path, "")
    local file = io.open(lockdir .. hash, "w")
    file:close()
end

local function delete(path)
    -- Both of the following methods cause the next photo to be lost / not stored.
    fa.remove(path)
    -- fa.request("http://127.0.0.1/upload.cgi?DEL="..path)
end

--Format file date to something meanigful
local function FatDateTimeToTable(datetime_fat)
    
    local function getbits(x, from, to)
        local mask = bit32.lshift(1, to - from + 1) - 1
        local shifted = bit32.rshift(x, from)
        return bit32.band(shifted, mask)
    end

    local fatdate = bit32.rshift(datetime_fat, 16)
    local day = getbits(fatdate, 0, 4)
    local month = getbits(fatdate, 5, 8)
    local year = getbits(fatdate, 9, 15) + 1980

    local fattime = getbits(datetime_fat, 0, 15)
    local sec = getbits(fattime, 0, 4) * 2
    local min = getbits(fattime, 5, 10)
    local hour = getbits(fattime, 11, 15)

    return {
    	year = string.format('%02d', year),
    	month = string.format('%02d', month),
    	day = string.format('%02d', day),
    	hour = string.format('%02d', hour), 
    	min = string.format('%02d', min),
    	sec = string.format('%02d', sec),
    }
end

--Looks for value in table
local function exists_in_table(tbl, val)
	for i = 1, #tbl do
		if (tbl[i] == val) then
			return true
		end
	end
	return false
end

local function create_thumbs()
	print("Creating Thumbs!")
	for i = 1, #dateTable do
		local message = "d="..dateTable[i]
		local headers = { 
			["Content-Length"] = string.len(message), 
			["Content-Type"] = "application/x-www-form-urlencoded"
		}
		local b, c, h = fa.request{
			url = "http://"..server.."/"..serverDir.."/ct.php",
			method = "POST",
			headers = headers,
            body = message
		}		
	end
	print("COMPLETE!")
end

local function upload_file(folder, file, subfolder)
    local path = folder .. "/" .. file
    -- Open the log file
    local outfile = io.open(logfile, "a")
    outfile:write(file .. " ... ")
    local url = ftpstring..subfolder.."/"..file
    local response = fa.ftp("put", url, path)
    --print("Uploading", url)
    
    --Check to see if it worked, and log the result!
    if response ~= nil then
        print("Success!")
        outfile:write(" Success!\n")
        set_uploaded(path)
        if delete_after_upload == true then
            print("Deleting " .. file)
            outfile:write("Deleting " .. file .. "\n")
            sleep(1000)
            delete(path)
            sleep(1000)
        end
    else
        print(" Fail ")
        outfile:write(" Fail\n")
    end

    --Close our log file
    outfile:close()
end

local function sort_upload_table()
	if (sortByFileName) then
		print("Sorting filenames alphabetically")
		table.sort(fileTable, function(a,b)
			return a.file>b.file 
		end)
	else
		print("Sorting filenames by modded date")
		table.sort(fileTable, function(a,b)
			return a.sortDate>b.sortDate
		end)
	end
end

local function run_upload()
	print("Starting upload")
	for i = 1, #fileTable do
		local ft = fileTable[i]
		print("Uploading:", ft.folder, ft.file, ft.dateString)
		upload_file(ft.folder, ft.file, ft.dateString)			
	end
	create_thumbs()
end

local function walk_directory(folder)

	parseThreads = parseThreads+1

	for file in lfs.dir(folder) do

	    local path = folder .. "/" .. file
	    local skip = string.sub( file, 1, 2 ) == "._"
	    local attr = lfs.attributes(path)
		local dt={}

	    if (not skip) then
	    	print( "Found "..attr.mode..": " .. path )
		    if attr.mode == "file" then
		    	local dateString = ""
				if (attr.modification~=nil) then
					dt = FatDateTimeToTable(attr.modification)
					dateString = dt.day.."-"..dt.month.."-"..dt.year
				end

		        if not is_uploaded(path) then
	        		if (not exists_in_table(blackList, dateString)) then
	        			local s,f = true, true
	        			if (jpegsOnly) then
	        				s,f = string.find(string.lower(file), ".jpg")
	        			end
	        			if (s and f) then
	        				fileTable[#fileTable+1] = 
	        				{
	        					folder = folder, 
	        					file = file, 
	        					dateString = dateString,
	        					sortDate=dt.year..dt.month..dt.day..dt.hour..dt.min..dt.sec
	        				}
							--upload_file(folder, file, dateString)
						end
					else
						print("Skipping ".. dateString.." - Blacklisted")
					end
		        else
		            print(path .. " previously uploaded, skipping")
		        end
		        
		    elseif attr.mode == "directory" then
		        print("Entering " .. path)
		        walk_directory(path)
			end
		end
	end

	parseThreads = parseThreads-1
	if (parseThreads == 0) then
		--create_thumbs()
		sort_upload_table()
		run_upload()
	end

end

local function create_folders(folder)
	if (#dateTable==0) then
		print("ERROR: DID NOT FIND ANY DATES!")
		return
	end
	for i = 1, #dateTable do
		local message = "d="..dateTable[i]
		local headers = { 
			["Content-Length"] = string.len(message), 
			["Content-Type"] = "application/x-www-form-urlencoded"
		}
		local b, c, h = fa.request{
			url = "http://"..server.."/"..serverDir.."/cd.php",
			method = "POST",
			headers = headers,
            body = message
		}
		
		if (b~=nil) then
			b = string.gsub(b, "\n", "")
			b = string.gsub(b, "\r", "")
		end
		
		if (b and b == "success") then
			print("SUCCESS FROM SERVER FOR FOLDER:"..dateTable[i].."<<")
		else
			print("FAILED RESPONSE FROM SERVER FOR FOLDER:"..dateTable[i].."<<")
			print("ADDING TO BLACKLIST")
			blackList[#blackList+1] = dateTable[i]
		end
	end
	print("OK FTP Starting...")
	walk_directory(folder)
end


local function get_folders(folder)
	parseThreads = parseThreads+1
	local tableCount = 1
	--Get the date range from the file
	for file in lfs.dir(folder) do	

		local path = folder .. "/" .. file
		local skip = string.sub( file, 1, 2 ) == "._"
		local attr = lfs.attributes(path)

		if (not skip) then
			if (attr.mode == "file") then
				print( "Datesearch Found "..attr.mode..": " .. path )
				local dateString = ""
				if (attr.modification~=nil) then
					local dt = FatDateTimeToTable(attr.modification)
					dateString = dt.day.."-"..dt.month.."-"..dt.year
				end
				if (not exists_in_table(dateTable, dateString)) then
					dateTable[#dateTable+1] = dateString
				end
			elseif attr.mode == "directory" then
		        print("Datesearch Entering " .. path)
		        get_folders(path)
			end
		end
	end

	parseThreads = parseThreads-1
	if (parseThreads == 0) then
		create_folders(folder)
	end
end

-- wait for wifi to connect
while string.sub(fa.ReadStatusReg(),13,13) ~= "a" do
    print("Wifi not connected. Waiting...")
    sleep(1000)
end

sleep(30*1000)
get_folders(folder)
