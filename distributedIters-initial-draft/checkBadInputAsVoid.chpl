/*
  Test to check the correctness of the distributed() iterator from the
  DistributedIters module.
*/
use DistributedIters;

// Range length.
config const n:int=10000;

var rng:range=1..n;

var A:[rng] int=0;

/*
  Input must be a range, domain, or array, so this should cause a compiler
  error.
*/
writeln("Checking a void...");
var v:void;
for i in distributed(v) do {
  A[i] = A[i]+1;
}
