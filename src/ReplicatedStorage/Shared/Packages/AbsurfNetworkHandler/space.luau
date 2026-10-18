local ByteNet = require(script.Parent.net)
return ByteNet.defineNamespace("Main", function()
	return {
		packets = {
			rely = ByteNet.definePacket({

				value = ByteNet.struct({

					Method = ByteNet.string,
					Info = ByteNet.optional(ByteNet.unknown),
					Timestamp = ByteNet.float64,

				}),

				reliabilityType = "reliable"

			}),

			unrely = ByteNet.definePacket({

				value = ByteNet.struct({

					Method = ByteNet.string,
					Info = ByteNet.optional(ByteNet.unknown),
					Timestamp = ByteNet.float64,

				}),

				reliabilityType = "unreliable",
			})

		},

		queries = {

			one = ByteNet.defineQuery({

				request = ByteNet.struct({

					Method = ByteNet.string,
					Info = ByteNet.optional(ByteNet.unknown),
					Timestamp = ByteNet.float64,

				}),

				response = ByteNet.struct({

					Info = ByteNet.optional(ByteNet.unknown),

				})

			})

		},

	}
end)
