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

// If true, write out only the test time result (ideal for shell scripts).
config const timing:bool = false;
// Print debugging output.
config const debug:bool = false;

/*
  Benchmark mode (iterator):

  default -- The block-distributed default iterator.
  guided -- The distributed guided load-balancing iterator.
*/
enum iterator
{
  default,
  guided
};
config const mode:iterator = iterator.guided;

/*
  Test cases for array values:

  constant -- All array elements have the same constant value.
  linear -- Array values follow some linear function (default y = x).
  normal -- Normally distributed, scaled to [0,1].
  outlier -- Most values close to average with handful of outliers.
  uniform -- Uniformly random.
*/
enum testCase
{
  constant,
  normal,
  identity,
  outlier,
  rampdown,
  rampup,
  uniform
};
config const test:testCase = testCase.uniform;

// Use this value for the constant test case.
config const constant:real = 0.4;

/*
  If coordinated is true, then the guided iterator dedicates one locale to
  distributing work to the remaining locales.
*/
config const coordinated:bool = false;

// n determines the iteration count and work per iteration.
config const n:int = 1000;

const controlRange:range = 0..#n;
const controlDomain:domain(1) = {controlRange};
const globalRandomSeed:int = 13;

select mode
{
  when iterator.default do testControlWorkload();
  when iterator.guided do testGuidedWorkload();
}

// Testing procedures.

proc testGuidedWorkload()
{
  if !timing
  then writeln("Using distributed guided iterator, running ", test,
               " test case...");
  var timer:Timer;

  const replicatedDomain:domain(1) dmapped Replicated() = controlDomain;
  var array:[controlDomain]real;
  var replicatedArray:[replicatedDomain]real;

  select test
  {
    when testCase.constant do fillConstant(array, constant);
    when testCase.identity do fillIdentity(array);
    when testCase.normal do fillNormallyDistributed(array);
    when testCase.outlier do fillLogisticOutliers(array);
    when testCase.rampdown do fillRampDown(array);
    when testCase.rampup do fillRampUp(array);
    when testCase.uniform do fillUniformlyRandom(array);
  }

  coforall L in Locales
  do on L do for i in controlDomain do replicatedArray[i] = array[i];

  if debug then writeArrayStatistics(array);

  timer.start();
  forall i in guidedDistributed(controlRange, coordinated=coordinated) do
  {
    const k:real = (array[i] * n):int;

    /*
    if i == n/2
    then for L in Locales
    do on L do writeln(here.locale, ": array[", i, "] = ", k);
    */

    // Performance for isPerfect seems too similar between balanced and
    // unbalanced for both guided and default.
    isPerfect(k:int);

    /* Replacing isPerfect with this, after we try completely uniform.
    const kPiApproximate:real = (k * piApproximate(k:int));
    const kPiApproximateBBP:real = (k * piApproximateBBP(kPiApproximate:int));
    const piApproximation:real = piApproximate(kPiApproximateBBP:int);
    */
  }
  timer.stop();

  if timing
  then writeln("%dr".format(timer.elapsed()));
  else writeln("Total test time (", test,
               ", n = ", n, ", nl = ", numLocales, "): ", timer.elapsed());
  timer.clear();
}

proc testControlWorkload()
{
  if !timing
  then writeln("Using default (control) iterator, running ", test,
               " test case...");

  var timer:Timer;

  const D:domain(1) dmapped Block(boundingBox=controlDomain) = controlDomain;
  var array:[D]real;

  select test
  {
    when testCase.constant do fillConstant(array, constant);
    when testCase.normal do fillNormallyDistributed(array);
    when testCase.identity do fillIdentity(array);
    when testCase.outlier do fillLogisticOutliers(array);
    when testCase.rampdown do fillRampDown(array);
    when testCase.rampup do fillRampUp(array);
    when testCase.uniform do fillUniformlyRandom(array);
  }

  if debug then writeArrayStatistics(array);

  timer.start();
  forall i in D do
  {
    const k:real = (array[i] * n):int;

    /*
    if i == n/2
    then for L in Locales
    do on L do writeln(here.locale, ": array[", i, "] = ", k);
    */

    // Performance for isPerfect seems too similar between balanced and
    // unbalanced for both guided and default.
    isPerfect(k:int);

    /* Replacing isPerfect with this, after we try completely uniform.
    const kPiApproximate:real = (k * piApproximate(k:int));
    const kPiApproximateBBP:real = (k * piApproximateBBP(kPiApproximate:int));
    const piApproximation:real = piApproximate(kPiApproximateBBP:int);
    */
  }
  timer.stop();

  if timing
  then writeln("%dr".format(timer.elapsed()));
  else writeln("Total test time (", test,
               ", n = ", n, ", nl = ", numLocales, "): ", timer.elapsed());

  timer.clear();
}

/*
  Array fills.
*/

proc fillArrayByElement(array, f)
{
  const arrayDomain = array.domain;
  forall i in arrayDomain do
  {
    const x = array[i];
    array[i] = f(x);
  }
}

proc fillArrayByIndex(array, f)
{
  const arrayDomain = array.domain;
  forall i in arrayDomain do array[i] = f(i);
}

proc fillConstant(array, constant)
{
  const arrayDomain = array.domain;
  forall i in arrayDomain do array[i] = constant;
}

proc fillLinear(array, slope, yIntercept)
{
  const arrayDomain = array.domain;
  forall i in arrayDomain do array[i] = ((slope * i) + yIntercept);
}

proc fillIdentity(array) { fillLinear(array, (1.0/n:real), 0); }
proc fillRampDown(array) { fillLinear(array, (-1.0/n:real), 1); }
proc fillRampUp(array) { fillLinear(array, (1.0/n:real), 0); }
proc fillUniformlyRandom(array) { fillRandom(array, globalRandomSeed); }

proc fillLogisticOutliers(array)
{
  const arrayDomain = array.domain;
  fillRandom(array, globalRandomSeed);
  /*
    This function creates extreme outliers using the logistic function:
    https://en.wikipedia.org/wiki/Logistic_function

    We use x_0 = 0.8 as the sigmoid's midpoint, L = 0.625 as the curve's
    maximum value, and k = 135.805 as the curve's slope, then translate it by
    0.375. This means the function

      0.625/(1 + e^(-135.805 * (x - 0.8))) + 0.375

    translates x values in the interval [0,1] such that ~80% are 0.375, ~20%
    are close to 1, and there is a steep value transition from 0.375 to 1.
  */
  const x_0:real = 0.8;
  const L:real = 0.625;
  const k:real = 135.805;
  const y_0:real = 0.375;
  forall i in arrayDomain do
  {
    const x:real = array[i];
    array[i] = ((0.625 / (1 + (Math.e ** (-135.805 * (x - 0.8))))) + 0.375);
  }
}

proc fillCubicOutliers(array)
{
  const arrayDomain = array.domain;
  fillRandom(array, globalRandomSeed);
  /*
    Creating outliers: a_3 through a_0 are coefficients for a cubic function
    extrapolation for these (x,y) points:

      {(0, 0.5), (0.25, 0.5), (0.5, 0.5), (0.75, 0.5), (1, 1)}.

    Thus the function

      a_3*x^3 + a_2*x^2 + a_1*x + a_0

    translates x values in the interval [0,1] into values that follow this
    distribution:

      ~80% are between 0.45 and 0.55,
      ~10% are between 0.55 and 0.75,
      ~5% are between 0.75 and 0.85,
      ~5% are between 0.85 and 1.
  */
  const a_3:real = 2.66667;
  const a_2:real = -2.85714;
  const a_1:real = 0.690476;
  const a_0:real = 0.492857;
  forall i in arrayDomain do
  {
    const x:real = array[i];
    const xSquared:real = (x ** 2);
    const xCubed:real = (x * xSquared);
    const translatedX:real = ((a_3 * xCubed)
                              + (a_2 * xSquared)
                              + (a_1 * x)
                              + a_0);
    array[i] = translatedX;
  }
}

proc fillNormallyDistributed(array)
{
  const arrayDomain = array.domain;
  fillRandom(array, globalRandomSeed);
  /*
    https://en.wikipedia.org/wiki/Normal_distribution#Alternative_parameterizations

      sigma is standard deviation (which should be "mean by three").
      precision is 1/sigma.
  */
  const mean:real = 0.5;
  const precision:int = 6;
  const precisionByRootTwoPi:real = (precision:real/((2.0 * Math.pi) ** 0.5));
  const minusPrecisionSquaredByTwo:real = (-1.0 * ((precision:real ** 2.0)
                                                   /2.0));
  forall i in arrayDomain do
  {
    const x:real = array[i];
    const power:real = (minusPrecisionSquaredByTwo
                        * ((x - mean) ** 2.0));
    const translatedX:real = (precisionByRootTwoPi * (Math.e ** power));
    array[i] = translatedX;

  }
  // Scale to have values between 0 and 1.
  array /= max(array);
}

// Helpers.

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
  var current:real = 0.0;
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
  Returns a pi approximation to n iterations using Bailey, Borwein, and
  Plouffe's formula.
  https://en.wikipedia.org/wiki/Approximations_of_%CF%80#Efficient_methods
*/
proc piApproximateBBP(n:int):real
{
  var current:real = 0.0;
  var eightK:real;
  for k in 0..n do
  {
    eightK = (8.0 * k:real);
    current += ((1.0/(16.0 ** k:real)) * ((4.0 / (eightK + 1.0))
                                          - (2.0 / (eightK + 4.0))
                                          - (1.0 / (eightK + 5.0))
                                          - (1.0 / (eightK + 6.0))));
  }
  return current;
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

proc max(array:[]):real
{
  var max:real;
  assert(array.size > 0, "max: array must have positive-size domain");
  const arrayLocalSubdomain = array.localSubdomain();
  const firstIndex = arrayLocalSubdomain.first;
  const initial = array[firstIndex];
  max = initial;
  for element in array do
  {
    if element > max then max = element;
  }
  return max;
}

proc writeArrayStatistics(array:[]real)
{ // Write the given array's min, max, mean, standard deviation, and histogram.
  var max,mean,min,squaredDeviationSum,stdDev,sum:real;
  const arraySize:int = array.size;
  if arraySize == 0
  then writeln("writeArrayStatistics: array has zero-size domain");
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

// EOF

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
