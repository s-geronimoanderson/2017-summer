use BugIteratorModule;

proc doppelganger()
{
  writeln("Main's proc.");
}

for i in moduleProc(1..#2) do
  writeln(i);
