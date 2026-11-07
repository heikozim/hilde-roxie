# The mutations of Roxie.Level, sourced by scripts/in-gate.sh.
mutations+=(
	"Level.hiq|s/constant wordMost: Index := 9;/constant wordMost: Index := 6;/|warning is too long a word"
	"Level.hiq|s/            return byte + 32;/            return byte;/|a word in capitals is another word"
	"Level.hiq|s/wordIs(text, first, stop, \"failed\") or //|failed is no error"
	"Level.hiq|s/                    if (rank > best) and/                    if (rank < best) and/|the least severe word wins"
	"Level.hiq|s/((byte >= 'a') and (byte <= 'z')) or ((byte >= 'A') and (byte <= 'Z'))/((byte >= 'a') and (byte <= 'z')) or false/|capitals end a word"
	"Level.hiq|s/            return \"warn\";/            return \"info\";/|warn is info"
	#: a count of nothing.
	"Level.hiq|s/                    if (rank > best) and (not zeroCount(text, first, i)) then/                    if rank > best then/|0 failed is error"
	"Level.hiq|s/            if (first = 2) or (not isWordByte(text\[first - 3\])) then/            if true then/|10 failed counts nothing"
	"Level.hiq|s/(text\[first - 1\] = ' ') and (text\[first - 2\] = '0')/text[first - 2] = '0'/|0-failed counts nothing"
	"Level.hiq|s/            while (at < size) and (text\[at\] = ' ') do/            while false do/|spaces after the colon end the count"
	"Level.hiq|s/            if (at < size) and (text\[at\] = '=') then/            if false then/|errors=0 is error"
	"Level.hiq|s/ or (text\[at + 1\] = '.')//|0.5 counts nothing"
	"Level.hiq|s/        if (at >= size) or (text\[at\] \/= '0') then/        if at >= size then/|any number counts nothing"
)
