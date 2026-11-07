# The mutations of Roxie.Reader, sourced by scripts/in-gate.sh.
mutations+=(
	"Reader.hiq|s/                                if not reader then/                                if false then/|the token of an agent opens a query"
	"Reader.hiq|s/        return startsWith(owner, prefix);/        return true;/|any owner a reader"
	"Reader.hiq|s/        if spanLength(owner) <= spanLength(prefix) then/        if false then/|the prefix alone a reader"
	"Reader.hiq|s/        if not get then/        if false then/|a POST answered"
	"Reader.hiq|s/        if (size = 0) or (size > mostNameBytes) then/        if size = 0 then/|a reader of any length"
	"Reader.hiq|s/            if not ((small or digit) or (b = '-')) then/            if false then/|a reader of any bytes"
	"Reader.hiq|s/        if (total < 1) or (total > mostShown()) then/        if false then/|a limit of 0 or over 100"
	"Reader.hiq|s/        if (size = 0) or (size > 3) then/        if false then/|an empty limit or one of 4 digits"
	"Reader.hiq|s/            if (b < '0') or (b > '9') then/            if false then/|a limit of other bytes"
	"Reader.hiq|s/        if status <= 1 then/        if status <= 3 then/|a refused query answered 200"
	"Reader.hiq|s/            return 400;/            return 200;/|a refused query answered 200 again"
)
