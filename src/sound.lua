-- The stim sound. The game plays only the sounds of the game's own sound banks, and a new sound there
-- means a new list of every sound in the game, which only one mod at a time can have. So this one plays
-- through Windows: winmm waveOut, through LuaJIT's FFI, with an output of its own, so it mixes with the
-- game and with other mods' sounds (PlaySound, which Custom Crosshair uses, has one sound per process
-- and a new one cuts the last short). It goes past the game's volume settings, so the mod has a volume
-- setting of its own.
local M = {}

M.HEAD = 44             -- bytes before the samples of a plain WAV
M.GAIN = 0.6            -- the full sound is as loud as a sound can be
M.NEAR = 25             -- metres: another player's stim is heard within this
M.FAR_GAIN = 0.45       -- and this loud, of the setting

-- The setting (0 to 1) to a share of the full sound: squared, as ears hear loudness on a log scale.
function M.gain(setting)
	setting = math.max(0, math.min(1, tonumber(setting) or 0))
	return M.GAIN * setting * setting
end

-- The samples of `wav` (a string) at `volume` (0 to 1) as a string, the header kept. Pure, for tests.
function M.scaled(wav, volume)
	volume = math.max(0, math.min(1, volume or 1))
	if volume >= 1 then return wav end
	local out = { wav:sub(1, M.HEAD) }
	local bytes = {}
	for i = M.HEAD + 1, #wav - 1, 2 do
		local lo, hi = wav:byte(i, i + 1)
		local v = lo + hi * 256
		if v >= 32768 then v = v - 65536 end
		v = math.floor(v * volume + 0.5)
		if v < 0 then v = v + 65536 end
		bytes[#bytes + 1] = string.char(v % 256, math.floor(v / 256))
		if #bytes >= 512 then
			out[#out + 1] = table.concat(bytes)
			bytes = {}
		end
	end
	out[#out + 1] = table.concat(bytes)
	return table.concat(out)
end

-- The format of a plain WAV: channels, rate, bits.
function M.format(wav)
	local function u16(at) local a, b = wav:byte(at, at + 1) return a + b * 256 end
	local function u32(at) return u16(at) + u16(at + 2) * 65536 end
	return u16(23), u32(25), u16(35)
end

local function find_ffi()
	local ok, ffi = pcall(require, "ffi")
	if ok and type(ffi) == "table" then return ffi end
	local loaded = type(package) == "table" and package.loaded
	if type(loaded) == "table" and type(loaded.ffi) == "table" then return loaded.ffi end
	return nil
end

local DECL = [[
typedef struct { uint16_t wFormatTag, nChannels; uint32_t nSamplesPerSec, nAvgBytesPerSec; uint16_t nBlockAlign, wBitsPerSample, cbSize; } stims_WAVEFORMATEX;
typedef struct stims_WAVEHDR { char *lpData; uint32_t dwBufferLength, dwBytesRecorded; uintptr_t dwUser; uint32_t dwFlags, dwLoops; struct stims_WAVEHDR *lpNext; uintptr_t reserved; } stims_WAVEHDR;
uint32_t waveOutOpen(void **phwo, uint32_t uDeviceID, const stims_WAVEFORMATEX *pwfx, uintptr_t dwCallback, uintptr_t dwInstance, uint32_t fdwOpen);
uint32_t waveOutPrepareHeader(void *hwo, stims_WAVEHDR *pwh, uint32_t cbwh);
uint32_t waveOutUnprepareHeader(void *hwo, stims_WAVEHDR *pwh, uint32_t cbwh);
uint32_t waveOutWrite(void *hwo, stims_WAVEHDR *pwh, uint32_t cbwh);
uint32_t waveOutReset(void *hwo);
uint32_t waveOutClose(void *hwo);
]]

-- A player for the variants (WAV strings, all of one format), or nil and why not. player.play(volume)
-- plays one at random at volume (0 to 1, of the full sound); a new play cuts the last short.
function M.new(variants)
	local ffi = find_ffi()
	if not ffi then return nil, "no FFI" end
	if ffi.os ~= "Windows" then return nil, "not Windows" end
	if not pcall(ffi.cdef, DECL) then return nil, "declarations" end
	local ok, winmm = pcall(ffi.load, "winmm")
	if not ok then return nil, "no winmm" end
	local channels, rate, bits = M.format(variants[1])
	local fmt = ffi.new("stims_WAVEFORMATEX")
	fmt.wFormatTag, fmt.nChannels, fmt.nSamplesPerSec, fmt.wBitsPerSample = 1, channels, rate, bits
	fmt.nBlockAlign = channels * bits / 8
	fmt.nAvgBytesPerSec = rate * fmt.nBlockAlign
	fmt.cbSize = 0
	local handle = ffi.new("void*[1]")
	if winmm.waveOutOpen(handle, 0xFFFFFFFF, fmt, 0, 0, 0) ~= 0 then return nil, "no output" end
	local hwo = handle[0]
	local size = ffi.sizeof("stims_WAVEHDR")
	local header = ffi.new("stims_WAVEHDR")
	local buffer, prepared = nil, false
	local cache = {} -- "<variant>:<volume step>" -> samples
	local player = {}
	function player.play(volume)
		local i = math.random(#variants)
		local step = math.floor(math.max(0, math.min(1, volume or 1)) * 20 + 0.5)
		if step == 0 then return false end
		local key = i .. ":" .. step
		local data = cache[key]
		if not data then
			data = M.scaled(variants[i], step / 20):sub(M.HEAD + 1)
			cache[key] = data
		end
		if prepared then
			winmm.waveOutReset(hwo)
			winmm.waveOutUnprepareHeader(hwo, header, size)
			prepared = false
		end
		-- The bytes stay in this player's buffer while Windows reads them.
		buffer = ffi.new("char[?]", #data)
		ffi.copy(buffer, data, #data)
		header.lpData, header.dwBufferLength, header.dwFlags, header.dwLoops = buffer, #data, 0, 0
		if winmm.waveOutPrepareHeader(hwo, header, size) ~= 0 then return false end
		prepared = true
		return winmm.waveOutWrite(hwo, header, size) == 0
	end
	function player.close()
		if prepared then
			winmm.waveOutReset(hwo)
			winmm.waveOutUnprepareHeader(hwo, header, size)
			prepared = false
		end
		winmm.waveOutClose(hwo)
	end
	return player
end

return M
