# The mutations of Roxie.Find, sourced by scripts/in-gate.sh.
mutations+=(
	"Find.hiq|s/        return (byte = 115) or (byte = 109) or (byte = 104) or (byte = 100) or (byte = 119);/        return (byte = 115) or (byte = 109) or (byte = 104) or (byte = 100);/|no week in --since"
	"Find.hiq|s/        return digitsOnly(substring(since, 0, size - 1), 9);/        return digitsOnly(substring(since, 0, size - 1), 10);/|a window of 10 digits"
	"Find.hiq|s/(spanLength(since) >= 9) and digitsOnly(since, 12)/(spanLength(since) >= 1) and digitsOnly(since, 12)/|24 as a second of 1970"
	"Find.hiq|s/(spanLength(since) >= 9) and digitsOnly(since, 12)/(spanLength(since) >= 9) and digitsOnly(since, 13)/|seconds of 13 digits"
	"Find.hiq|s/        if (since\[4\] \/= 45) or (since\[7\] \/= 45) then/        if since\[4\] \/= 45 then/|a day without its second minus"
	"Find.hiq|s/            writeString(\&!out, \") and time:last \");/            writeString(\&!out, \") or time:last \");/|the window joined with or"
	"Find.hiq|s/            writeString(\&!out, \" .. \");/            writeString(\&!out, \" ..\");/|a range without its space"
	"Find.hiq|s/        if total = 0 then/        if total < 0 then/|nothing found is lines found"
	"Find.hiq|s/                        return failed(2, \"refused\"/                        return failed(4, \"refused\"/|a refusal as the store"
	"Find.hiq|s/                return failed(2, \"since\"/                return failed(3, \"since\"/|a refused --since as too many lines"
	"Find.hiq|s/        writeName(\&~writer, \"schema\");/        writeName(\&~writer, \"scheme\");/|another name of the schema"
	"Find.hiq|s/                            writeName(\&!writer, \"line\");/                            writeName(\&!writer, \"text\");/|the text of a line under another name"
	"Find.hiq|s/                            writeString(\&!text, asSpan(\&level));/                            writeString(\&!text, asSpan(\&source));/|the source where the level belongs"
	"Find.hiq|s/            if line\[stop - 1\] = 10 then/            if false then/|the line end kept"
	"Find.hiq|s/            if verbose then/            if false then/|-v says nothing"
	"Find.hiq|s/                writeInteger(\&!writer, wide(at));/                writeNull(\&!writer);/|a refusal without its byte"
)
