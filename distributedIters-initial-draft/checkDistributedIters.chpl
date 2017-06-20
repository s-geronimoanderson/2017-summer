/*
  Test to check the correctness of the distributed() iterator from the
  DistributedIters module.
*/
use BlockDist;
use DistributedIters;

/*
  Control variables. These determine the test variables (defined later) and
  provide control for checking correctness.
*/
config const n:int=1000;
var controlRange:range=1..n;

// Variations.
var controlStridedRange=controlRange by 2;
var controlCountedRange=controlRange # 5;
var controlStridedCountedRange=controlStridedRange # 5;
var controlAlignedRange=controlStridedRange align 1;
var controlDomain:domain(1)={controlRange};

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

var testGuidedDistributedRangeArray:[controlRange] int=0;

writeln("Testing a range (distributed guided iterator)...");
forall i in guided(controlRange) do
  testGuidedDistributedRangeArray[i] = testGuidedDistributedRangeArray[i]+1;
checkCorrectness(testGuidedDistributedRangeArray,controlRange);

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

/*
  Domains.
*/
var testDomain:domain(1)=controlDomain;
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
var testDomainArray:[testDomain] int=0;

writeln("Testing a domain...");
for i in distributed(testDomain) do {
  testDomainArray[i] = testDomainArray[i]+1;
}
checkCorrectness(testDomainArray,controlDomain);


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
var testArray:[controlDomain] int=0;

writeln("Testing an array...");
for i in distributed(testArray) do {
  testArray[i] = testArray[i]+1;
}
checkCorrectness(testArray,controlDomain);

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
  Helper functions.
*/
proc checkCorrectness(Arr:[]int,c)
{
  var check=true;
  for i in c do
  {
    //writeln("Checking: ", i, ", which is ", Arr[i]);
    if Arr[i] != 1 then
    {
      check=false;
      writeln(" ");
      writeln("Error in iteration ", i);
      writeln(" ");
    }
  }
  writeln("Result: ",
          if check==true
          then "pass"
          else "fail");
}

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
