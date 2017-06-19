/*
  Test to check that the distributed() iterator from the DistributedIters
  module accepts all valid inputs (ranges, domains, and arrays).
*/
use BlockDist;
use DistributedIters;

// Common variables.
config const n:int=10000;
var rng:range=0..n;
var A:[rng] int=0;

/*
  Ranges.
*/
var testRange:range=0..n;
var testStridedRange=testRange by 2;
var testCountedRange=testRange # 5;
var testStridedCountedRange=testStridedRange # 5;
var testAlignedRange=testStridedRange align 1;

writeln("Checking a range...");
for i in distributed(testRange) do {
  A[i] = A[i]+1;
}

writeln("Checking a strided range...");
for i in distributed(testStridedRange) do {
  A[i] = A[i]+1;
}

writeln("Checking a counted range...");
for i in distributed(testCountedRange) do {
  A[i] = A[i]+1;
}

writeln("Checking a strided counted range...");
for i in distributed(testStridedCountedRange) do {
  A[i] = A[i]+1;
}

writeln("Checking an aligned range...");
for i in distributed(testAlignedRange) do {
  A[i] = A[i]+1;
}

/*
  Domains.
*/
var testEmptyDomain:domain(1);
const testDomainLiteral={1..n};
var testAssociativeDomain:domain(int);
testAssociativeDomain += 3;
var testSparseDomain:sparse subdomain(testDomainLiteral);
const testBlockDistributedDomain={1..n} dmapped
  Block(boundingBox={1..n});

writeln("Checking an empty domain...");
for i in distributed(testEmptyDomain) do {
  A[i] = A[i]+1;
}

writeln("Checking a domain literal...");
for i in distributed(testDomainLiteral) do {
  A[i] = A[i]+1;
}

writeln("Checking an associative domain...");
for i in distributed(testAssociativeDomain) do {
  A[i] = A[i]+1;
}

writeln("Checking a sparse domain...");
for i in distributed(testSparseDomain) do {
  A[i] = A[i]+1;
}

writeln("Checking a block distributed domain...");
for i in distributed(testBlockDistributedDomain) do {
  A[i] = A[i]+1;
}

/*
  Arrays.
*/
const testArrayDomain={1..n};
var testArray:[testArrayDomain] int;
const testArrayDistributedDomain={1..n} dmapped
  Block(boundingBox={1..n});
var testDistributedArray:[testArrayDistributedDomain] int;

writeln("Checking an array...");
for i in distributed(testArray) do {
  A[i] = A[i]+1;
}

writeln("Checking a distributed array...");
for i in distributed(testDistributedArray) do {
  A[i] = A[i]+1;
}
