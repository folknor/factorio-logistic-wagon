#!/usr/bin/lua
local VERSION = 2
-- lua5.2 release script for factorio mods
-- by folk@folk.wtf
-- Requires https://github.com/zserge/luash and https://github.com/whiteinge/ok.sh
-- Remember to set up ~/.netrc
--
-- LICENSE CC-BY-SA 3.0 https://creativecommons.org/licenses/by-sa/3.0

local sh = require("sh")
local _ = tostring
local source = _(curl("-s", "https://raw.githubusercontent.com/folknor/factorio-release-script/master/release.lua"))
if type(source) == "string" then
	local currentVersion = tonumber(source:match("local VERSION = (%d+)"))
	if type(currentVersion) == "number" and currentVersion > VERSION then
		local answer
		repeat
			io.write("There is a new version of factorio-release-script available, do you want to exit (y/n)? ")
			io.flush()
			answer = io.read()
		until answer == "y" or answer == "n"
		if answer == "y" then return end
	end
end

local oksh = sh.command("ok.sh")
local function exit(...) io.write(..., "\n") os.exit() end

local maj, min, patch = tonumber((select(1, ...))), tonumber((select(2, ...))), tonumber((select(3, ...)))
if type(maj) ~= "number" or type(min) ~= "number" or type(patch) ~= "number" then exit("Please provide an additive version number bump, like 0 0 10, 0 1 0, 1 0 2, or 0 0 0 for no bump.") end

local mod = _(cat("info.json"))
local name = mod:match("\"name\":%s+\"(%S+)\"")
if type(name) ~= "string" or name:len() < 5 then exit("Could not parse name from info.json.") end
local oMaj, oMin, oPatch = tonumber(mod:match("\"version\":%s+\"(%d+).%d+.%d+\"")), tonumber(mod:match("\"version\":%s+\"%d+.(%d+).%d+\"")), tonumber(mod:match("\"version\":%s+\"%d+.%d+.(%d+)\""))
if type(oMaj) ~= "number" or type(oMin) ~= "number" or type(oPatch) ~= "number" then exit("Failed to parse mod version from info.json.") end

local lastTag = _(git("describe", "--tags", "--abbrev=0", "HEAD^"))
local changes = "body=\"" .. _(git("log", lastTag .. "..HEAD", "--pretty=format:\"* %s\"")) .. "\""

local version = "%d.%d.%d"
if maj ~= 0 or min ~= 0 or patch ~= 0 then
	version = version:format(oMaj + maj, oMin + min, oPatch + patch)
	sed("-i", ("'s/\"version\": \"[0-9]\\+.[0-9]\\+.[0-9]\\+\"/\"version\": %q/g'"):format(version), "info.json")
	git("add", "info.json")
	git("commit", "-m", "\"Prerelease version bump.\"")
	git("push")
else
	version = version:format(oMaj, oMin, oPatch)
end

local tag = "v" .. version
git("tag", tag)
git("push", "origin", tag) -- Commit the tag before we do the release post

if type(changes) == "string" then
	local repo = _(git("rev-parse", "--show-toplevel")):match("^.*/(%w+)$")
	oksh("create_release", "folknor", repo, tag, changes)
end

local tuple = name .. "_" .. version
git("archive", "--prefix=" .. tuple .. "/", "--output=" .. tuple .. ".zip", "HEAD")
