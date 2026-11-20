# bash_utilities

## How to grep stderr of a command. 

    command 2>&1 1> /dev/null | grep "pattern"

Step-by-Step Breakdown

The shell evaluates pipes first and then processes redirections strictly from
left to right:

| Step	| Syntax	|What Happens Under the Hood |
| ----- | --------- | --------------------------- |
| 1. Pipe setup | \| grep "pattern"	| Before running command, the shell creates a pipe to grep and points command's stdout (1) into that pipe. (stderr (2) still points to your terminal screen). |
| 2. Redirect stderr | 	2>&1 |	File descriptor 2 (stderr) is copied to point to wherever file descriptor 1 (stdout) is currently pointing—which is the grep pipe. |
| 3. Discard stdout | 	1>/dev/null	| File descriptor 1 (stdout) is redirected to /dev/null. Because 2 was already pointed directly at the pipe in Step 2, moving 1 now does not affect 2.  |
| 4. Filter	 | grep "pattern" |	grep reads from its standard input (the pipe), which now contains only what command sent to stderr.|

