# The mutations of Roxie.Outbox, sourced by scripts/in-gate.sh.
mutations+=(
	"Outbox.hiq|s/                if text\[textEnd - 1\] = 13 then/                if false then/|a carriage return kept"
	"Outbox.hiq|s/(((lines + 1) > mostBatchLines())/(((lines + 1) > (mostBatchLines() + 1))/|a batch of 1001 lines"
	"Outbox.hiq|s/ or ((bytes + need) > mostBatchBytes()))/ or false)/|a batch over 1 MiB"
	"Outbox.hiq|s/        if not isSource(path) then/        if false then/|a path that is no source"
	"Outbox.hiq|s/ORDER BY number LIMIT 1/ORDER BY number DESC LIMIT 1/|the newest batch first"
	"Outbox.hiq|s/lines, ? FROM roxie_outbox WHERE number = ?/lines, ? FROM roxie_outbox WHERE number < 0 AND number = ?/|a refused batch dropped, not kept aside"
	"Outbox.hiq|s/                return Right(right => changed > 0);/                return Right(right => true);/|a batch taken that was not there"
	"Outbox.hiq|s/            count := count + 1;/            count := count + 2;/|lines counted twice"
	"Outbox.hiq|s/ WHERE NOT EXISTS (SELECT 1 FROM sqlite_sequence WHERE name = 'roxie_outbox')//|a second start of the numbers"
)
