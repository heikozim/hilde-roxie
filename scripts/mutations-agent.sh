# The mutations of Roxie.Agent, sourced by scripts/in-gate.sh.  Sending
# itself is checked end to end (scripts/in-e2e.sh), not in this round.
mutations+=(
	"Agent.hiq|s/        if status = 200 then/        if status = 201 then/|200 is no batch taken"
	"Agent.hiq|s/        if status = 400 then/        if status = 401 then/|a token refused sets a batch aside"
	"Agent.hiq|s/constant tokenDigits: Index := 64;/constant tokenDigits: Index := 63;/|a token of 63 digits"
	"Agent.hiq|s/((byte >= 'a') and (byte <= 'f'))/((byte >= 'A') and (byte <= 'f'))/|capitals in a token"
	"Agent.hiq|s/ or (text\[stop - 1\] = 13)) or / or false) or /|a carriage return kept in a token"
	"Agent.hiq|s/constant sendsMost: Int64 := 100;/constant sendsMost: Int64 := 101;/|101 batches a round"
	"Agent.hiq|s/        if report.keptBack or (report.setAside > 0) then/        if report.keptBack then/|a batch set aside waits for the line of the rounds"
	"Agent.hiq|s/        if report.keptBack or (report.setAside > 0) then/        if report.setAside > 0 then/|a batch kept back waits for the line of the rounds"
	"Agent.hiq|s/        if (tally.collected = 0) and (tally.taken = 0) then/        if false then/|rounds that moved nothing are said"
	"Agent.hiq|s/        if (tally.said = 0) or (now < tally.said) then/        if now < tally.said then/|the first line after the start waits"
	"Agent.hiq|s/        if (tally.said = 0) or (now < tally.said) then/        if tally.said = 0 then/|a clock gone back waits"
	"Agent.hiq|s/        return (now - tally.said) >= every;/        return (now - tally.said) > every;/|the line of the rounds a second late"
	"Agent.hiq|s/ or ((report.setAside > 0) or report.keptBack);/ or ((report.setAside > 0) or false);/|a batch kept back moved nothing"
	"Agent.hiq|s/setAside => tally.setAside + report.setAside, rounds => tally.rounds + 1,/setAside => report.setAside, rounds => tally.rounds + 1,/|the batches set aside not added up"
)
