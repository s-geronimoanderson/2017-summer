module BugIteratorModule
{

proc doppelganger()
{
  writeln("Module proc.");
}

iter moduleProc(c)
{
  doppelganger();
  yield c;
}

} // End of module.
