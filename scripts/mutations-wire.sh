# The mutations of Roxie.Wire, sourced by scripts/in-gate.sh.
mutations+=(
	"Wire.hiq|s/constant batchLinesMost: Index := 1000;/constant batchLinesMost: Index := 1001;/|1001 lines in a batch"
	"Wire.hiq|s/constant batchBytesMost: Index := 1048576;/constant batchBytesMost: Index := 2097152;/|a batch of 2 MiB"
	"Wire.hiq|s/constant textMost: Index := 16384;/constant textMost: Index := 16385;/|a text of 16385 bytes"
	"Wire.hiq|s/constant skewMost: Int64 := 300;/constant skewMost: Int64 := 301;/|a line 301 seconds ahead"
	"Wire.hiq|s/constant timeDigitsMost: Index := 12;/constant timeDigitsMost: Index := 13;/|a time of 13 digits"
	"Wire.hiq|s/constant headerStart: Span\[Nat8, Static\] := \"roxie 1 \";/constant headerStart: Span[Nat8, Static] := \"roxie 2 \";/|another version of the batch"
	"Wire.hiq|s/                if number < 1 then/                if false then/|batch 0"
	"Wire.hiq|s/        if not isSource(substring(data, tab2 + 1, tab3)) then/        if false then/|a line without a source"
	"Wire.hiq|s/            let control: Bool := ((byte < 32) and (byte \/= 9)) or (byte = 127);/            let control: Bool := false;/|a control byte in a text"
	"Wire.hiq|s/                writeByte(\&~out, ' ');/                writeByte(\&~out, byte);/|a control byte written as it is"
	"Wire.hiq|s/        if not (isLevel(level) and isSource(source)) then/        if false then/|a line of no level written"
	"Wire.hiq|s/        if (at - skewMost) > now then/        if false then/|a time of the future"
	"Wire.hiq|s/        let fixed: Index := 16;/        let fixed: Index := 15;/|a line counted a byte short"
	"Wire.hiq|s/        if first = size then/        if false then/|a batch without lines"
	"Wire.hiq|s/            if count > batchLinesMost then/            if count >= batchLinesMost then/|1000 lines refused"
)
