-- The harness every *_test.lua shares (run.js runs this first in each test's state): eq and near count
-- a check each and fail at the caller's line; a test returns checks(), the count run.js prints.
local count = 0

function eq(actual, expected, what)
	count = count + 1
	if actual ~= expected then
		error(string.format("%s: expected [%s], got [%s]", what, tostring(expected), tostring(actual)), 2)
	end
end

function near(actual, expected, what)
	count = count + 1
	if math.abs(actual - expected) > 1e-9 then
		error(string.format("%s: expected %s, got %s", what, tostring(expected), tostring(actual)), 2)
	end
end

function checks()
	return count
end

-- The Encode facade's files in the TOC's order: ns.Encode is all of them (Store/Encode.lua).
local loadChunk = load
function loadEncode(ns)
	for _, file in ipairs({ "Encode.lua", "EncodeIds.lua", "EncodeText.lua", "EncodeAmounts.lua" }) do
		assert(loadChunk(SOURCES[file], "@" .. file))("GoldForever", ns)
	end
end
