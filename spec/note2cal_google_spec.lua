describe("note2cal.google.util", function()
	local util = require("note2cal.google.util")

	describe("url_encode / url_decode", function()
		it("round-trips reserved and unicode-unsafe characters", function()
			local raw = "4/0AX4XfWi some code+with/slash&and=equals"
			assert.equal(raw, util.url_decode(util.url_encode(raw)))
		end)

		it("encodes spaces and slashes for a query component", function()
			assert.equal("1%201", util.url_encode("1 1"))
			assert.equal("a%2Fb", util.url_encode("a/b"))
		end)
	end)

	describe("build_query", function()
		it("produces sorted, percent-encoded key=value pairs", function()
			assert.equal("a=1%201&b=2", util.build_query({ b = "2", a = "1 1" }))
		end)

		it("omits nil values", function()
			assert.equal("a=1", util.build_query({ a = "1", b = nil }))
		end)
	end)

	describe("to_rfc3339_utc", function()
		it("converts a local wall-clock time to the matching UTC instant", function()
			local epoch = os.time({ year = 2025, month = 1, day = 20, hour = 15, min = 0, sec = 0 })
			local expected = os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
			assert.equal(expected, util.to_rfc3339_utc(2025, 1, 20, 15, 0))
		end)

		it("resolves the correct offset across a DST boundary", function()
			local winter_epoch = os.time({ year = 2025, month = 1, day = 20, hour = 12, min = 0, sec = 0 })
			local summer_epoch = os.time({ year = 2025, month = 7, day = 20, hour = 12, min = 0, sec = 0 })

			assert.equal(
				os.date("!%Y-%m-%dT%H:%M:%SZ", winter_epoch),
				util.to_rfc3339_utc(2025, 1, 20, 12, 0)
			)
			assert.equal(
				os.date("!%Y-%m-%dT%H:%M:%SZ", summer_epoch),
				util.to_rfc3339_utc(2025, 7, 20, 12, 0)
			)
		end)
	end)

	describe("is_token_expired", function()
		it("treats a missing token or missing expires_at as expired", function()
			assert.is_true(util.is_token_expired(nil))
			assert.is_true(util.is_token_expired({}))
		end)

		it("is false for a token comfortably within its lifetime", function()
			assert.is_false(util.is_token_expired({ expires_at = os.time() + 3600 }))
		end)

		it("is true once past expires_at", function()
			assert.is_true(util.is_token_expired({ expires_at = os.time() - 10 }))
		end)

		it("applies the safety margin so refresh happens slightly early", function()
			local token = { expires_at = os.time() + 30 }
			assert.is_true(util.is_token_expired(token, nil, 60))
			assert.is_false(util.is_token_expired(token, nil, 10))
		end)
	end)

	describe("random_state", function()
		it("returns a non-empty string that differs across calls", function()
			local a, b = util.random_state(), util.random_state()
			assert.is_true(#a > 0)
			assert.are_not.equal(a, b)
		end)
	end)
end)
