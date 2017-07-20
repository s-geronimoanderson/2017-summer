/*
  Benchmarks for testing the performance of the distributed() iterator from the
  DistributedIters module.

  Part of a 2017 Cray summer intern project by Sean I. Geronimo Anderson
  (sgeronimo@cray.com) as mentored by Ben Harshbarger (bharshbarg@cray.com).
*/
use BlockDist,
    DistributedItersSandbox,
    Math,
    Random,
    ReplicatedDist,
    Sort,
    Time;

/*
  Loads:

  pi -- Iterated pi approximation. Jupiter: 43 s with 4 tasks (n = 100,000)
  perfect -- Check if numbers are perfect. Kaibab: 20 s with 4 tasks (n = 10,000)
  harmonic -- Check if numbers are harmonic divisors. Kaibab: 30 s with 4 tasks
              (n = 10,000)
*/
// TODO: Have tests accept these overrides (currently defaults to pi).
enum calculation { pi, perfect, harmonic };
config const load:calculation = calculation.pi;

/*
  Test cases:

  uniformlyrandom -- Self-explanatory. Uses guided distributed iterator.
  uniformlyrandomcontrol -- Same as above but with default iterator.

  outlier -- Most values close to average, handful of outliers.
  outliercontrol -- Same as above but with default iterator.
*/
enum testCase
{
  normal,
  normalcontrol,
  outlier,
  outliercontrol,
  uniformlyrandom,
  uniformlyrandomcontrol
};
config const test:testCase = testCase.uniformlyrandom;

config const coordinated:bool = false;
// n determines the iteration count and work per iteration.
config const n:int = 1000;

const controlRange:range = 0..#n;
const controlDomain:domain(1) = {controlRange};

select test
{
  /*
    Test #1: Iterate over a range that maps to a list of uniform random integers.
    Do some work proportional to the value of the integers.
  */
  when testCase.uniformlyrandom
  {
    writeln("Testing a uniformly random workload...");

    /*
    writeln("... guidedDistributed iterator, default-distributed domain:");
    testUniformlyRandomWorkload(
      arrayDomain=controlDomain,
      iterator=guidedDistributed(controlDomain, coordinated=coordinated),
      procedure=piApproximate);
    */

    writeln("... guidedDistributed iterator, replicated distribution:");
    const replicatedDomain:domain(1) dmapped ReplicatedDist() = controlDomain;
    testUniformlyRandomWorkload(
      arrayDomain=replicatedDomain,
      iterator=guidedDistributed(controlDomain, coordinated=coordinated),
      procedure=piApproximate);
  }
  when testCase.uniformlyrandomcontrol
  {
    writeln("Testing a uniformly random workload...");
    writeln("... default (control) iterator, block-distributed array:");
    const D:domain(1) dmapped Block(boundingBox=controlDomain) = controlDomain;
    testUniformlyRandomWorkload(
      arrayDomain=D,
      iterator=D,
      procedure=piApproximate);
  }

  /*
    Test #2: Iterate over a range that maps to values that are mostly the same
    except for a handful of much larger values to throw off the balance.
  */
  when testCase.outlier
  {
    writeln("Testing a random outliers workload...");
    writeln("... guidedDistributed iterator, replicated distribution:");
    const replicatedDomain:domain(1) dmapped ReplicatedDist() = controlDomain;
    testRandomOutliersWorkload(
      arrayDomain=replicatedDomain,
      iterator=guidedDistributed(controlDomain, coordinated=coordinated),
      procedure=piApproximate);
  }
  when testCase.outliercontrol
  {
    writeln("Testing a random outliers workload...");
    writeln("... default (control) iterator, block-distributed array:");
    const D:domain(1) dmapped Block(boundingBox=controlDomain) = controlDomain;
    testRandomOutliersWorkload(
      arrayDomain=D,
      iterator=D,
      procedure=piApproximate);
  }

  /*
    Test #3: Iterate over a range that maps to values that are follow a normal
    distribution.
  */
  when testCase.normal
  {
    writeln("Testing a normally-distributed workload...");
    writeln("... guidedDistributed iterator, replicated distribution:");
    const replicatedDomain:domain(1) dmapped ReplicatedDist() = controlDomain;
    testNormallyDistributedWorkload(
      arrayDomain=replicatedDomain,
      iterator=guidedDistributed(controlDomain, coordinated=coordinated),
      procedure=piApproximate);
  }
  when testCase.normalcontrol
  {
    writeln("Testing a normally-distributed workload...");
    writeln("... default (control) iterator, block-distributed array:");
    const D:domain(1) dmapped Block(boundingBox=controlDomain) = controlDomain;
    testNormallyDistributedWorkload(
      arrayDomain=D,
      iterator=D,
      procedure=piApproximate);
  }
}

// Testing procedures.

proc testWorkload(array:[], iterator, procedure)
{
  var timer:Timer;
  writeArrayStatistics(array);
  timer.start();
  forall i in iterator do
  {
    const k:int = (array[i] * n):int;
    procedure(k);
  }
  timer.stop();
  writeln("Total test time: ", timer.elapsed());
  timer.clear();
}

proc testUniformlyRandomWorkload(arrayDomain, iterator, procedure)
{
  var uniformlyRandom:[arrayDomain]real = 0.0;
  fillRandom(uniformlyRandom);
  testWorkload(uniformlyRandom, iterator, procedure);
}

proc testRandomOutliersWorkload(arrayDomain, iterator, procedure)
{
  var randomOutliers:[arrayDomain]real = 0.0;
  fillRandom(randomOutliers);
  /*
    Creating outliers: a_3 through a_0 are coefficients for a cubic function
    extrapolation for these (x,y) points:

      {(0, 0.5), (0.25, 0.5), (0.5, 0.5), (0.75, 0.5), (1, 1)}.

    The function translates x values in the interval [0,1] into values that
    follow this distribution:

      ~80% are between 0.45 and 0.55,
      ~10% are between 0.55 and 0.75,
      ~5% are between 0.75 and 0.85,
      ~5% are between 0.85 and 1.
  */
  const a_3:real = 2.66667;
  const a_2:real = 2.85714;
  const a_1:real = 0.690476;
  const a_0:real = 0.492857;
  forall i in arrayDomain do
  {
    const x:real = randomOutliers[i];
    const xSquared:real = (x ** 2);
    const xCubed:real = (x * xSquared);
    const translatedX:real = ((a_3 * xCubed)
                              - (a_2 * xSquared)
                              + (a_1 * x)
                              + a_0);
    randomOutliers[i] = translatedX;
  }
  testWorkload(randomOutliers, iterator, procedure);
}

proc testNormallyDistributedWorkload(arrayDomain, iterator, procedure)
{
  var normallyDistributed:[arrayDomain]real = 0.0;
  fillRandom(normallyDistributed);
  /*
    https://en.wikipedia.org/wiki/Normal_distribution#Alternative_parameterizations

      sigma is standard deviation (which should be "mean by three").
      precision is 1/sigma.
  */
  const mean:real = 0.5;
  const precision:int = 6;
  const precisionByRootTwoPi:real = (precision:real/Math.sqrt(2*Math.pi));
  const minusPrecisionSquaredByTwo:real = (-1.0 * ((precision:real ** 2.0)
                                                   /2.0));
  forall i in arrayDomain do
  {
    const x:real = normallyDistributed[i];
    /*
    const power:real = (minusPrecisionSquaredByTwo
                        * ((x - mean) ** 2.0));
    const translatedX:real = (precisionByRootTwoPi * (Math.e ** power));
    */
    const translatedX:real = ((6.0 / Math.sqrt(2.0 * Math.pi))
                              * (Math.e
                                 ** (-18.0
                                     * ((x - 0.5)
                                        ** 2.0))));
    normallyDistributed[i] = translatedX;

  }
  testWorkload(normallyDistributed, iterator, procedure);
}

// Helpers.

iter fibo(n:int)
{ // Yields the Fibonacci sequence from the zeroth number to the nth.
  var current:int=0,
      next:int=1;
  for i in 0..n
  {
    yield current;
    current += next;
    current <=> next;
  }
}

iter fact(n:int)
{ // Yields the factorial sequence from zero factorial up to n factorial.
  assert(n >= 0, "n must be a nonnegative integer");
  var current:int=1;
  if n == 0
  then yield 1;
  else
  {
    yield 1;
    for i in 1..n
    {
      current *= i;
      yield current;
    }
  }
}

/*
  Yields up to k successive refinements of the Taylor series (at a = 0) for
  the exponential function e ** x.
  https://en.wikipedia.org/wiki/Taylor_series
*/
iter expoSeries(x:real,k:int=30):real
{
  var current:real=0.0;
  for (n_factorial,n) in zip(fact(k),0..k)
  {
    current += (x ** n) / n_factorial;
    yield current;
  }
}

/*
  Yields a pi approximation to k iterations using Fabrice Bellard's formula.
  https://en.wikipedia.org/wiki/Approximations_of_%CF%80#Efficient_methods
*/
iter piFabriceBellard(k:int)
{
  var current:real=0.0;
  var fourN, tenN : int;
  for n in 0..k do
  {
    fourN = 4*n;
    tenN = 10*n;
    current += ((((-1) ** n)/2 ** tenN) * (-(32/(fourN + 1))
                                           - (1/(fourN + 3))
                                           + (256/(tenN + 1))
                                           - (64/(tenN + 3))
                                           - (4/(tenN + 5))
                                           - (4/(tenN + 7))
                                           + (1/(tenN + 9))));
  }
  yield current/64;
}

/*
  Yields a pi approximation to n iterations using Bailey, Borwein, and
  Plouffe's formula.
  https://en.wikipedia.org/wiki/Approximations_of_%CF%80#Efficient_methods
*/
iter piBBP(n:int)
{
  var current:real=0.0;
  var eightK:int;
  for k in 0..n do
  {
    eightK = 8*k;
    current += ((1/(16**k)) * ((4/(eightK + 1))
                               - (2/(eightK + 4))
                               - (1/(eightK + 5))
                               - (1/(eightK + 6))));
    yield current;
  }
}

iter primeSieve(n:int)
{ // Sieve of Eratosthenes: Yield all primes up to n.
  var p:int=2;
  var composite:[p..#n] bool;
  while p <= n do
  {
    yield p;
    for i in 2*p..n by p do
      composite[i] = true;
    var i:int=p+1;
    while composite[i] do i += 1;
    p = i;
  }
}

/*
  Returns a pi approximation using Fabrice Bellard's formula for k iterations.
  https://en.wikipedia.org/wiki/Approximations_of_%CF%80#Efficient_methods
*/
proc piApproximate(k:int):real
{
  var current:real=0.0;
  var fourN,tenN:real;
  for n in 0..k do
  {
    fourN = 4*n;
    tenN = 10*n;
    current += ((((-1) ** n)/2 ** tenN) * (-(32/(fourN + 1))
                                           - (1/(fourN + 3))
                                           + (256/(tenN + 1))
                                           - (64/(tenN + 3))
                                           - (4/(tenN + 5))
                                           - (4/(tenN + 7))
                                           + (1/(tenN + 9))));
  }
  return current/64.0;
}

/*
  Integer factorization. Transliterated from Python version on Wikipedia.
  (Python version commented on right for reference.)

  Source:
  https://en.wikipedia.org/wiki/Trial_division
*/
proc trialDivision(n:int):domain(int)  // def trialDivision(n):
{ // Returns an associative domain of  // """Return a list of the prime
  // n's prime factors.                //    factors for a natural
                                       //    number."""
  if n < 2 then                        // if n < 2:
    return {1..0};                     //   return []
  var x:int=n; // Needed for Chapel.   // x = n # Needed for Chapel.
  var primeFactors:domain(int);        // primeFactors = []
  for p in primeSieve((x**0.5):int)    // for p in primeSieve(int(x**0.5)):
  {                                    //
    if p*p > x then break;             //   if p*p > x: break
    while x % p == 0 do                //   while x % p == 0:
    {                                  //
      primeFactors += p;               //     primeFactors.append(p)
      x = divfloorpos(x,p);            //     x //= p
    }                                  //
  }                                    //
  if x > 1 then                        // if x > 1:
    primeFactors += x;                 //   primeFactors.append(x)
  return primeFactors;                 // return primeFactors
}

proc properDivisors(n:int):domain(int)
{
  var result:domain(int)={1};
  var quotient:real;
  for i in 2..n/2 do
  {
    quotient=n/i;
    if quotient == quotient:int
    then result += i;
  }
  return result;
}

proc divisors(n:int):domain(int)
{
  return properDivisors(n) + n;
}

proc isPerfect(n:int):bool
{
  var properDivisorsN:domain(int)=properDivisors(n);
  var sum:int;
  for p in properDivisorsN do sum += p;
  return sum == n;
}

/*
  A harmonic divisor number, or Ore number, is a positive integer whose
  divisors have a harmonic mean that is an integer.
  https://en.wikipedia.org/wiki/Harmonic_divisor_number
*/
proc isHarmonicDivisor(n:int):bool
{
  if n < 1 then return false;
  if n == 1 then return true;
  var numerator,denominator,harmonicMean:real;
  var divisorsN:domain(int) = divisors(n);
  numerator = divisorsN.size;
  for p in divisorsN do denominator += 1.0/(p:real);
  harmonicMean = (numerator/denominator);
  /*
    TODO: We would like to do this here:

      return harmonicMean == round(harmonicMean)

    But, we cannot, because for n = 6, we get harmonicMean = 2.0 but
    ceil(harmonicMean) = 3.0. That is, the harmonic mean calculation includes
    some infinitesmial amount such that the above desired comparison
    expression fails even when it should succeed. We could use some kind of
    fraction representation with algebraic manipulation to make this
    procedure work correctly... but currently it does not. It is still good as
    a dummy load for benchmarking.
  */
  return harmonicMean == round(harmonicMean);
}

proc writeArrayStatistics(array:[]real)
{ // Write the given array's min, max, mean, standard deviation, and histogram.
  var max,mean,min,squaredDeviationSum,stdDev,sum:real;
  const arraySize:int = array.size;
  if arraySize == 0
  then writeln("writeArrayStatistics: array has zero-length domain");
  else
  {
    // Initial.
    const arrayLocalSubdomain = array.localSubdomain();
    const firstIndex = arrayLocalSubdomain.first;
    const initial = array[firstIndex];
    min = initial;
    max = initial;

    // Mean.
    for element in array do
    {
      if element < min then min = element;
      if element > max then max = element;
      sum += element;
    }
    mean = (sum/arraySize:real);

    // Standard deviation.
    for element in array do squaredDeviationSum += ((element - mean) ** 2.0);
    stdDev = ((squaredDeviationSum/arraySize:real) ** (0.5));

    writeln("writeArrayStatistics: min = ", min,
            ", max = ", max,
            ", mean = ", mean,
            ", stdDev = ", stdDev);

    // Histogram. Bin by stdDev.
    var bins:[0..7]int;
    const minusStdDev:real = (mean - stdDev);
    const minusTwoStdDev:real = (mean - 2.0*stdDev);
    const minusThreeStdDev:real = (mean - 3.0*stdDev);
    const plusStdDev:real = (mean + stdDev);
    const plusTwoStdDev:real = (mean + 2.0*stdDev);
    const plusThreeStdDev:real = (mean + 3.0*stdDev);
    for element in array do
    {
      if element < mean
      then if element < minusTwoStdDev
           then if element < minusThreeStdDev
                then bins[0] += 1;
                else bins[1] += 1;
           else if element < minusStdDev
                then bins[2] += 1;
                else bins[3] += 1;
      else if element < plusTwoStdDev
           then if element < plusStdDev
                then bins[4] += 1;
                else bins[5] += 1;
           else if element < plusThreeStdDev
                then bins[6] += 1;
                else bins[7] += 1;
    }
    writeln("writeArrayStatistics: Histogram:");
    var current:real = minusThreeStdDev;
    for bin in bins do
    {
      writeln((current - stdDev), " to ", current, ": ", bin);
      current += stdDev;
    }
  }
}

proc writeArrayValueHistogram(a:[])
{ // Write the given array's values histogram.
  // TODO: Parameterize bin width?
  var firstQuarter,secondQuarter,thirdQuarter,fourthQuarter:int;
  for i in a do
  {
    const k:int=(i * n):int;
    if k < n:real/4
    then firstQuarter += 1;
    else if k < n:real/2
         then secondQuarter += 1;
         else if k < n:real*3/4
              then thirdQuarter += 1;
              else fourthQuarter += 1;
  }
  writeln("0-", n:real/4 - 1/n:real, ": ", firstQuarter,
          ", ", n:real/4, "-", n:real/2 - 1/n:real, ": ", secondQuarter,
          ", ", n:real/2, "-", n:real*3/4 - 1/n:real, ": ", thirdQuarter,
          ", ", n:real*3/4, "-", n:real - 1/n:real, ": ", fourthQuarter);
}
