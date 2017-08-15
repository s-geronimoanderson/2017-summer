/*
  Tests for verifying correctness of the distributedGuided() iterator from the
  DistributedIters module.

  Test cases:
  - Range inputs
  - Domain inputs
*/
use DistributedIters;

/*
  Control variables. These determine the test variables (defined later) and
  help us check correctness.
*/
config const coordinated:bool = false;
config const n:int = 1000;
config const numTasks:int = 0;

const controlRange:range = 1..n;
const controlRangeStrided = (controlRange by 2);

const controlDomain:domain(1) = {controlRange};
const controlDomainStrided = (controlDomain by 2);

/*
  Range inputs.
*/
writeln("Testing a range, non-strided (serial)...");
var rNSS:[controlRange]int;
for i in distributedGuided(controlRange,
                           coordinated=coordinated,
                           numTasks=numTasks)
do rNSS[i] = (rNSS[i] + 1);
checkCorrectness(rNSS, controlRange);

writeln("Testing a range, non-strided (zippered)...");
var rNSZ:[controlRange, controlRange]int;
forall (i,j) in zip(distributedGuided(controlRange,
                                      coordinated=coordinated,
                                      numTasks=numTasks),
                    controlRange)
do rNSZ[i,j] = (rNSZ[i,j] + 1);
checkCorrectnessZippered(rNSZ, controlRange, controlRange);

writeln("Testing a range, strided (serial)...");
var rSS:[controlRangeStrided]int;
for i in distributedGuided(controlRangeStrided,
                           coordinated=coordinated,
                           numTasks=numTasks)
do rSS[i] = (rSS[i] + 1);
checkCorrectness(rSS, controlRangeStrided);

writeln("Testing a range, strided (zippered)...");
var rSZ:[controlRangeStrided, controlRange]int;
forall (i,j) in zip(distributedGuided(controlRangeStrided,
                                      coordinated=coordinated,
                                      numTasks=numTasks),
                    (controlRange # controlRangeStrided.size))
do rSZ[i,j] = (rSZ[i,j] + 1);
checkCorrectnessZippered(rSZ, controlRangeStrided, controlRange);

/*
  Domain inputs.
*/
writeln("Testing a domain, non-strided (serial)...");
var dNSS:[controlDomain]int;
for i in distributedGuided(controlDomain,
                           coordinated=coordinated,
                           numTasks=numTasks)
do dNSS[i] = (dNSS[i] + 1);
checkCorrectness(dNSS, controlDomain);

writeln("Testing a domain, non-strided (zippered)...");
var dNSZ:[controlRange, controlRange]int;
forall (i,j) in zip(distributedGuided(controlDomain,
                                      coordinated=coordinated,
                                      numTasks=numTasks),
                    controlDomain)
do dNSZ[i,j] = (dNSZ[i,j] + 1);
checkCorrectnessZippered(dNSZ, controlDomain, controlDomain);

writeln("Testing a domain, strided (serial)...");
var dSS:[controlDomainStrided]int;
for i in distributedGuided(controlDomainStrided,
                           coordinated=coordinated,
                           numTasks=numTasks)
do dSS[i] = (dSS[i] + 1);
checkCorrectness(dSS, controlDomainStrided);

writeln("Testing a domain, strided (zippered)...");
var dSZ:[controlRangeStrided, controlRange]int;
forall (i,j) in zip(distributedGuided(controlDomainStrided,
                                      coordinated=coordinated,
                                      numTasks=numTasks),
                    (controlDomain # controlDomainStrided.size))
do dSZ[i,j] = (dSZ[i,j] + 1);
checkCorrectnessZippered(dSZ, controlDomainStrided, controlDomain);

/*
  Helper functions.
*/
proc checkCorrectness(array:[]int, c)
{
  var check:bool = true;
  for i in c do
  {
    if (array[i] != 1) then
    {
      check = false;
      writeln();
      writeln("Error in iteration ", i);
      writeln();
    }
  }
  writeln("Result: ",
          if (check == true)
          then "pass"
          else "fail");
}

proc checkCorrectnessZippered(array:[]int, cLeader, cFollower)
{
  var check:bool = true;
  for (i,j) in zip(cLeader, cFollower#cLeader.size) do
  {
    if (array(i,j) != 1)
    then
    {
      check = false;
      writeln();
      writeln("Error in iteration (", i, ",", j, ")");
      writeln();
    }
  }
  writeln("Result: ",
          if (check == true)
          then "pass"
          else "fail");
}

// EOF
