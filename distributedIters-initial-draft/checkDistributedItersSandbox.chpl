/*
  Tests for verifying the DistributedIters module iterator correctness.

  Test cases:
  - Range inputs
  - Domain inputs
  - Specific work locales
  - Coordinated mode
*/
use DistributedItersSandbox;

/*
  Control variables. These determine the test variables (defined later) and
  help us check correctness.
*/
config const n:int = 1000;
config const numTasks:int = 0;

const controlRange:range = 1..n;
const controlRangeStrided = (controlRange by 2);

const controlDomain:domain(1) = {controlRange};
const controlDomainStrided = (controlDomain by 2);

/*
  Default tests.
*/
testRangesAndDomainsSerial();
testRangesAndDomainsZippered();

/*
  Specific work locales.
*/
if numLocales > 1 then
{
  const evenLocales = [Locale in Locales] if (Locale.id % 2 == 0) then Locale;
  const oddLocales = [Locale in Locales] if (Locale.id % 2 != 0) then Locale;

  testRangesAndDomainsZippered(workerLocales=evenLocales);
  testRangesAndDomainsZippered(workerLocales=oddLocales);

  // Coordinated mode.
  testRangesAndDomainsZippered(workerLocales=evenLocales, coordinated=true);
  testRangesAndDomainsZippered(workerLocales=oddLocales, coordinated=true);
}

/*
  Main testing functions.
*/
proc testRangesAndDomainsSerial()
{
  /*
    Range inputs.
  */
  writeln("Testing a range, non-strided (serial)...");
  var rNSS:[controlRange]int;
  for i in distributedGuided(controlRange,
                             numTasks=numTasks)
  do rNSS[i] = (rNSS[i] + 1);
  checkCorrectness(rNSS, controlRange);

  writeln("Testing a range, strided (serial)...");
  var rSS:[controlRangeStrided]int;
  for i in distributedGuided(controlRangeStrided,
                             numTasks=numTasks)
  do rSS[i] = (rSS[i] + 1);
  checkCorrectness(rSS, controlRangeStrided);

  /*
    Domain inputs.
  */
  writeln("Testing a domain, non-strided (serial)...");
  var dNSS:[controlDomain]int;
  for i in distributedGuided(controlDomain,
                             numTasks=numTasks)
  do dNSS[i] = (dNSS[i] + 1);
  checkCorrectness(dNSS, controlDomain);

  writeln("Testing a domain, strided (serial)...");
  var dSS:[controlDomainStrided]int;
  for i in distributedGuided(controlDomainStrided,
                             numTasks=numTasks)
  do dSS[i] = (dSS[i] + 1);
  checkCorrectness(dSS, controlDomainStrided);
}

proc testRangesAndDomainsZippered(workerLocales=Locales, coordinated=false)
{
  /*
    Range inputs.
  */
  writeln("Testing a range, non-strided (zippered)...");
  var rNSZ:[controlRange, controlRange]int;
  forall (i,j) in zip(distributedGuided(controlRange,
                                        coordinated=coordinated,
                                        numTasks=numTasks,
                                        workerLocales=workerLocales),
                      controlRange)
  do rNSZ[i,j] = (rNSZ[i,j] + 1);
  checkCorrectnessZippered(rNSZ, controlRange, controlRange);

  writeln("Testing a range, strided (zippered)...");
  var rSZ:[controlRangeStrided, controlRange]int;
  forall (i,j) in zip(distributedGuided(controlRangeStrided,
                                        coordinated=coordinated,
                                        numTasks=numTasks,
                                        workerLocales=workerLocales),
                      (controlRange # controlRangeStrided.size))
  do rSZ[i,j] = (rSZ[i,j] + 1);
  checkCorrectnessZippered(rSZ, controlRangeStrided, controlRange);

  /*
    Domain inputs.
  */
  writeln("Testing a domain, non-strided (zippered)...");
  var dNSZ:[controlRange, controlRange]int;
  forall (i,j) in zip(distributedGuided(controlDomain,
                                        coordinated=coordinated,
                                        numTasks=numTasks,
                                        workerLocales=workerLocales),
                      controlDomain)
  do dNSZ[i,j] = (dNSZ[i,j] + 1);
  checkCorrectnessZippered(dNSZ, controlDomain, controlDomain);

  writeln("Testing a domain, strided (zippered)...");
  var dSZ:[controlRangeStrided, controlRange]int;
  forall (i,j) in zip(distributedGuided(controlDomainStrided,
                                        coordinated=coordinated,
                                        numTasks=numTasks,
                                        workerLocales=workerLocales),
                      (controlDomain # controlDomainStrided.size))
  do dSZ[i,j] = (dSZ[i,j] + 1);
  checkCorrectnessZippered(dSZ, controlDomainStrided, controlDomain);
}

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



// Variations.
/*
var controlStridedRange=controlRange by 2;
var controlCountedRange=controlRange # 5;
var controlStridedCountedRange=controlStridedRange # 5;
var controlAlignedRange=controlStridedRange align 1;
var controlDomain:domain(1)={controlRange};
*/

/*
  Serial version.
*/
/*
writeln("Testing distributed guided iterator, serial version:");
// Range.
writeln("Testing range...");
var rangeDistributedGuidedArray:[controlRange] int=0;
const testRange:range = controlRange;
for i in distributedGuided(testRange) do
  rangeDistributedGuidedArray[i] = (rangeDistributedGuidedArray[i]+1);
checkCorrectness(rangeDistributedGuidedArray,controlRange);

// Domain.
writeln("Testing domain...");
var domainDistributedGuidedArray:[controlRange] int=0;
const testDomain:domain(1) = controlDomain;
for i in distributedGuided(testDomain) do
  domainDistributedGuidedArray[i] = (domainDistributedGuidedArray[i]+1);
checkCorrectness(domainDistributedGuidedArray,controlRange);

// Array (single).
writeln("Testing single array...");
var sameDistributedGuidedArray:[controlRange] int=0;
for i in distributedGuided(sameDistributedGuidedArray) do
  sameDistributedGuidedArray[i] = (sameDistributedGuidedArray[i]+1);
checkCorrectness(sameDistributedGuidedArray,controlRange);

// Array (separate).
writeln("Testing separate array...");
var separateDistributedGuidedArray:[controlRange] int=0;
const testArray:[controlDomain]int;
for i in distributedGuided(testArray) do
  separateDistributedGuidedArray[i] = (separateDistributedGuidedArray[i]+1);
checkCorrectness(separateDistributedGuidedArray,controlRange);
*/

/*
  Ranges.
*/

/* Commenting out while working on distributed guided.
var testRangeArray:[controlRange] int=0;

writeln("Testing a range...");
for i in distributed(controlRange) do
  testRangeArray[i] = testRangeArray[i]+1;
checkCorrectness(testRangeArray,controlRange);
*/

/* // Works fine.
writeln("Testing a range (distributed guided iterator)...");
var testGuidedDistributedRangeArray:[controlRange] int=0;
timer.start();
forall i in guidedDistributed(controlRange,
                              coordinated=coordinated,
                              numTasks=numTasks) do
  testGuidedDistributedRangeArray[i] = testGuidedDistributedRangeArray[i]+1;
timer.stop();
writeln("Time (", n, "): ", timer.elapsed());
timer.clear();

checkCorrectness(testGuidedDistributedRangeArray,controlRange);

writeln("Testing a range (reference guided iterator)...");
var testReferenceGuidedRangeArray:[controlRange] int=0;
timer.start();
forall i in guided(controlRange, numTasks=numTasks) do
  testReferenceGuidedRangeArray[i] = testReferenceGuidedRangeArray[i]+1;
timer.stop();
writeln("Time (", n, "): ", timer.elapsed());
timer.clear();

//checkCorrectness(testReferenceGuidedRangeArray,controlRange);
*/ // End works fine.



//recreationVersion(n);

proc recreationVersion(totalWork:int=n, processorCount:int=4)
/*
  Range recreation version, O(lg^2(n) * lg^2(lg(n))) serial time complexity.
  Possible iteration errors due to computer arithmetic.
*/
{
  const denseRange:range = 0..#n;
  var myAtomic:atomic int;

  var current = myAtomic.fetchAdd(1);
  var myRange = guidedSubrange(denseRange, processorCount, current);

  while myRange.low < denseRange.length do
  {
    writeln("yielding ", myRange);
    current = myAtomic.fetchAdd(1);
    myRange = guidedSubrange(denseRange, processorCount, current);
  }
}

proc geometricVersion(totalWork:int=n, processorCount:int=4)
/*
  Geometric version, O(lg n) serial time complexity.
  Possible iteration errors due to computer arithmetic.
*/
{
  const scaleFactor:real=totalWork:real/processorCount:real;
  const commonRatio:real=(1.0 - 1.0/processorCount:real);
  const cutoffGlobalCount:int=(log(processorCount:real/totalWork:real)
                               / log(commonRatio)):int;
  const lastKnownGoodLocalIndex:int=(totalWork:real
                                     * (1.0
                                        - commonRatio ** cutoffGlobalCount)):int;
  writeln("totalWork = ", totalWork,
          ", processorCount = ", processorCount,
          ", processorCount / totalWork = ", (processorCount:real/totalWork:real));
  writeln("scaleFactor = ", scaleFactor,
          ", commonRatio = ", commonRatio,
          ", cutoff = ", cutoffGlobalCount,
          ", last = ", lastKnownGoodLocalIndex);

  var commonRatioToTheCurrentIndex:real;
  var globalCount:int=0;
  var localIndex,localCount:real;
  var nextCommonRatioToTheN:real;
  var nextLocalIndex,newLocalCount:real;

  var i,currentIndex:int=0;

  // Start.
  currentIndex=globalCount;
  globalCount += 1;

  while currentIndex <= cutoffGlobalCount do
  {
    commonRatioToTheCurrentIndex = commonRatio**currentIndex;
    localIndex = totalWork * (1.0 - commonRatioToTheCurrentIndex);
    nextCommonRatioToTheN = commonRatio**(currentIndex+1);
    nextLocalIndex = totalWork * (1.0 - nextCommonRatioToTheN);
    newLocalCount = nextLocalIndex - localIndex;
    writeln(currentIndex, ": localIndex = ", localIndex,
            " (", localIndex:int,
            "), next = ", nextLocalIndex,
            " (", nextLocalIndex:int,
            "), newCount = ", newLocalCount,
            " (", newLocalCount:int,
            "), yielding ", localIndex:int..nextLocalIndex:int-1);
    currentIndex=globalCount;
    globalCount += 1;
  }
  writeln("globalCount = ", globalCount);
  writeln("Burning up the rest of the range...");

  localIndex = lastKnownGoodLocalIndex + (currentIndex-cutoffGlobalCount);

  while localIndex < totalWork do
  {
    writeln(currentIndex, ": localIndex = ", localIndex,
            " (", localIndex:int,
            "), next = ", localIndex+1,
            " (", localIndex+1:int,
            "), yielding ", localIndex:int..localIndex:int);
    currentIndex=globalCount;
    globalCount += 1;
    localIndex = lastKnownGoodLocalIndex + (currentIndex-cutoffGlobalCount);
  }
}

/*
writeln("Testing a strided range...");
for i in distributed(testStridedRange) do {
  A[i] = A[i]+1;
}

writeln("Testing a counted range...");
for i in distributed(testCountedRange) do {
  A[i] = A[i]+1;
}

writeln("Testing a strided counted range...");
for i in distributed(testStridedCountedRange) do {
  A[i] = A[i]+1;
}

writeln("Testing an aligned range...");
for i in distributed(testAlignedRange) do {
  A[i] = A[i]+1;
}
*/









//var testDomain:domain(1)=controlDomain;
/*
var testEmptyDomain:domain(1);
const testDomainLiteral={1..n};
var testAssociativeDomain:domain(int);
testAssociativeDomain += 3;
var testSparseDomain:sparse subdomain(testDomainLiteral);
const testBlockDistributedDomain={1..n} dmapped
  Block(boundingBox={1..n});
*/

//Arrays for verifying correctness.
//var testDomainArray:[testDomain] int=0;

/* Benchmarking.
writeln("Testing a domain...");
for i in distributed(testDomain) do {
  testDomainArray[i] = testDomainArray[i]+1;
}
checkCorrectness(testDomainArray,controlDomain);
End benchmarking. */

/*
writeln("Testing an empty domain...");
for i in distributed(testEmptyDomain) do {
  A[i] = A[i]+1;
}

writeln("Testing a domain literal...");
for i in distributed(testDomainLiteral) do {
  A[i] = A[i]+1;
}

writeln("Testing an associative domain...");
for i in distributed(testAssociativeDomain) do {
  A[i] = A[i]+1;
}

writeln("Testing a sparse domain...");
for i in distributed(testSparseDomain) do {
  A[i] = A[i]+1;
}

writeln("Testing a block distributed domain...");
for i in distributed(testBlockDistributedDomain) do {
  A[i] = A[i]+1;
}
*/

/*
  Arrays.
*/
//var testArray:[controlDomain] int=0;

/* Benchmarking.
writeln("Testing an array...");
for i in distributed(testArray) do {
  testArray[i] = testArray[i]+1;
}
checkCorrectness(testArray,controlDomain);
End benchmarking. */

/*
const testArrayDomain={1..n};
var testArray:[testArrayDomain] int;
const testArrayDistributedDomain={1..n} dmapped
  Block(boundingBox={1..n});
var testDistributedArray:[testArrayDistributedDomain] int;

writeln("Testing an array...");
for i in distributed(testArray) do {
  A[i] = A[i]+1;
}

writeln("Testing a distributed array...");
for i in distributed(testDistributedArray) do {
  A[i] = A[i]+1;
}
*/


/*
// Experiments.
writeln("continuousDomain:");
const continuousDomain = {0..7};
print(continuousDomain);

writeln("stridedDomain:");
const stridedDomain = continuousDomain by 2;
print(stridedDomain);

writeln("densifiedStridedDomain:");
const densifiedStridedDomain = densify(stridedDomain,stridedDomain);
print(densifiedStridedDomain);

writeln("unDensifiedStridedDomain:");
const unDensifiedStridedDomain = unDensify(densifiedStridedDomain,
                                           stridedDomain);
print(unDensifiedStridedDomain);

// Let's try this densification.
var powersOfTwo:[continuousDomain] int=0;
for i in continuousDomain do powersOfTwo[i] = 2**i;

iter jumanji(c)
{
  yield 1;
}

writeln("powersOfTwo for stridedDomain:");
for i in stridedDomain do writeln(powersOfTwo[i]);

writeln("powersOfTwo for densifiedStridedDomain:");
for i in densifiedStridedDomain do writeln(powersOfTwo[i]);


// Print iterables.
proc print(c)
{
  for i in c do write(i, " ");
  writeln();
}
// End experiments.
*/
