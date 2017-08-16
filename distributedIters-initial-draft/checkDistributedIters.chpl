/*
  Tests for verifying correctness and performance of the distributedGuided()
  iterator from the DistributedIters module.

  Test cases:
  - Range inputs
  - Domain inputs
*/
use DistributedIters;

config const checkCorrectness:bool = false;
config const coordinated:bool = false;
config const n:int = 1000;
config const numTasks:int = 0;

if verifyArray then
{
  /*
    Control constants. These determine the test variables (defined below) and
    help us check correctness.
  */
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
  verifyArray(rNSS, controlRange);

  writeln("Testing a range, non-strided (zippered)...");
  var rNSZ:[controlRange, controlRange]int;
  forall (i,j) in zip(distributedGuided(controlRange,
                                        coordinated=coordinated,
                                        numTasks=numTasks),
                      controlRange)
  do rNSZ[i,j] = (rNSZ[i,j] + 1);
  verifyArrayZippered(rNSZ, controlRange, controlRange);

  writeln("Testing a range, strided (serial)...");
  var rSS:[controlRangeStrided]int;
  for i in distributedGuided(controlRangeStrided,
                             coordinated=coordinated,
                             numTasks=numTasks)
  do rSS[i] = (rSS[i] + 1);
  verifyArray(rSS, controlRangeStrided);

  writeln("Testing a range, strided (zippered)...");
  var rSZ:[controlRangeStrided, controlRange]int;
  forall (i,j) in zip(distributedGuided(controlRangeStrided,
                                        coordinated=coordinated,
                                        numTasks=numTasks),
                      (controlRange # controlRangeStrided.size))
  do rSZ[i,j] = (rSZ[i,j] + 1);
  verifyArrayZippered(rSZ, controlRangeStrided, controlRange);

  /*
    Domain inputs.
  */
  writeln("Testing a domain, non-strided (serial)...");
  var dNSS:[controlDomain]int;
  for i in distributedGuided(controlDomain,
                             coordinated=coordinated,
                             numTasks=numTasks)
  do dNSS[i] = (dNSS[i] + 1);
  verifyArray(dNSS, controlDomain);

  writeln("Testing a domain, non-strided (zippered)...");
  var dNSZ:[controlRange, controlRange]int;
  forall (i,j) in zip(distributedGuided(controlDomain,
                                        coordinated=coordinated,
                                        numTasks=numTasks),
                      controlDomain)
  do dNSZ[i,j] = (dNSZ[i,j] + 1);
  verifyArrayZippered(dNSZ, controlDomain, controlDomain);

  writeln("Testing a domain, strided (serial)...");
  var dSS:[controlDomainStrided]int;
  for i in distributedGuided(controlDomainStrided,
                             coordinated=coordinated,
                             numTasks=numTasks)
  do dSS[i] = (dSS[i] + 1);
  verifyArray(dSS, controlDomainStrided);

  writeln("Testing a domain, strided (zippered)...");
  var dSZ:[controlRangeStrided, controlRange]int;
  forall (i,j) in zip(distributedGuided(controlDomainStrided,
                                        coordinated=coordinated,
                                        numTasks=numTasks),
                      (controlDomain # controlDomainStrided.size))
  do dSZ[i,j] = (dSZ[i,j] + 1);
  verifyArrayZippered(dSZ, controlDomainStrided, controlDomain);
}
else // checkCorrectness == false, so do performance testing.
{

}

/*
  Correctness testing procedures.
*/
proc verifyArray(array:[]int, c)
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

proc verifyArrayZippered(array:[]int, cLeader, cFollower)
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

/*
  Performance testing procedures.
*/
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
    when testCase.constant do fillConstant(array);
    when testCase.kryptonite do fillKryptonite(array);
    when testCase.normal do fillNormallyDistributed(array);
    when testCase.outlier do fillCubicOutliers(array);
    when testCase.rampdown do fillRampDown(array);
    when testCase.rampup do fillRampUp(array);
    when testCase.stacked do fillStacked(array);
    when testCase.uniform do fillUniformlyRandom(array);
  }

  coforall L in Locales
  do on L
  do for i in controlDomain
  do replicatedArray[i] = array[i];

  if debug then writeArrayStatistics(array);

  timer.start();
  forall i in distributedGuided(controlRange, coordinated=coordinated) do
  {
    const k:real = (array[i] * n):int;

    // Simulate work.
    isPerfect(k:int);
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
    when testCase.constant do fillConstant(array);
    when testCase.kryptonite do fillKryptonite(array);
    when testCase.normal do fillNormallyDistributed(array);
    when testCase.outlier do fillCubicOutliers(array);
    when testCase.rampdown do fillRampDown(array);
    when testCase.rampup do fillRampUp(array);
    when testCase.stacked do fillStacked(array);
    when testCase.uniform do fillUniformlyRandom(array);
  }

  if debug then writeArrayStatistics(array);

  timer.start();
  forall i in D do
  {
    const k:real = (array[i] * n):int;

    // Simulate work.
    isPerfect(k:int);
  }
  timer.stop();

  if timing
  then writeln("%dr".format(timer.elapsed()));
  else writeln("Total test time (", test,
               ", n = ", n, ", nl = ", numLocales, "): ", timer.elapsed());
  timer.clear();
}

/*
  Performance testing array fills.
*/
proc fillConstant(array, constant=1)
{
  const arrayDomain = array.domain;
  forall i in arrayDomain do array[i] = constant;
}

proc fillLinear(array, slope, yIntercept)
{
  const arrayDomain = array.domain;
  forall i in arrayDomain do array[i] = ((slope * i) + yIntercept);
  normalizeSum(array);
}

proc fillRampDown(array) { fillLinear(array, (-1.0/n:real), 1.0); }
proc fillRampUp(array) { fillLinear(array, (1.0/n:real), 0); }

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
    array[i] = (0.8 * translatedX);
  }
  normalizeSum(array);
}

proc fillKryptonite(array, desiredProcessorCount:int=0)
{
  const processorCount:int = if desiredProcessorCount == 0
                             then if dataParTasksPerLocale == 0
                                  then here.maxTaskPar
                                  else dataParTasksPerLocale
                             else desiredProcessorCount;
  const arrayDomain = array.domain;
  const arraySize:int = array.size;
  /*
    This fill uses the guided iterator's behavior against it by putting almost
    all the work into the first work unit, using the same closed-form
    expression that the iterator uses for dividing work units.
  */
  const lengthOverProcessorCount:real = (arraySize:real
                                         / processorCount:real);
  const commonRatio:real = (1.0 - (1.0 / processorCount:real));

  forall i in arrayDomain do
  {
    array[i] = (lengthOverProcessorCount * (commonRatio ** i));
  }
  normalizeSum(array);
}

proc fillStacked(array, desiredProcessorCount:int=0)
{
  const processorCount:int = if desiredProcessorCount == 0
                             then if dataParTasksPerLocale == 0
                                  then here.maxTaskPar
                                  else dataParTasksPerLocale
                             else desiredProcessorCount;
  const arrayDomain = array.domain;
  const arraySize:int = array.size;
  /*
    The opposite of fillKryptonite, this fill supports the guided iterator's
    behavior by ensuring each work unit contains an equal amount of work.
  */
  const lengthOverProcessorCount:real = (arraySize:real
                                         / processorCount:real);
  const commonRatio:real = (1.0 - (1.0 / processorCount:real));

  forall i in arrayDomain do
  {
    array[i] = (lengthOverProcessorCount * (commonRatio ** (arraySize - i)));
  }
  normalizeSum(array);
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
  normalizeSum(array);
}

proc fillUniformlyRandom(array)
{
  fillRandom(array, globalRandomSeed);
  normalizeSum(array);
}

/*
  Performance testing helpers.
*/
proc normalizeSum(array, desiredSum=0)
{ // Make an array's sum equal its size by scaling all values appropriately.
  const arrayDomain = array.domain;
  const targetSum:int = if desiredSum == 0
                        then array.size
                        else desiredSum;
  var sum:real;

  for i in arrayDomain do sum += array[i];
  const scalingFactor:real = (targetSum / sum);
  array *= scalingFactor;
}

proc properDivisors(n:int):domain(int)
{ // Return an associative domain of ``n``'s proper divisors.
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

proc isPerfect(n:int):bool
{ /*
    Return whether ``n`` is a perfect number (i.e. equals its proper divisor
    sum).
  */
  var properDivisorsN:domain(int)=properDivisors(n);
  var sum:int;
  for p in properDivisorsN do sum += p;
  return sum == n;
}

proc max(array:[]):real
{ // Return the maximum value in ``array``.
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
{ // Write ``array``'s min, max, mean, sum, standard deviation, and histogram.
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
            ", stdDev = ", stdDev,
            ", sum = ", sum);

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
