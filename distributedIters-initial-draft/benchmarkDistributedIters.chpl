/*
  Benchmarks for testing the performance of the distributed() iterator from the
  DistributedIters module.

  Part of a 2017 Cray summer intern project by Sean I. Geronimo Anderson
  (sgeronimo@cray.com) as mentored by Ben Harshbarger (bharshbarg@cray.com).
*/
use DistributedIters,
    Math,
    Random,
    Sort,
    Time;
/*
  Control variables. These determine the test variables (defined later) and
  provide control for checking correctness.
*/
config const n:int=100;
var controlRange:range=0..n;

/*
  Iterate over a range that maps to a list of uniform random integers.
  Do some work proportional to the value of the integers.
*/
writeln("Testing a uniformly random workload...");
var uniformlyRandomWorkload:[controlRange] real=0.0;
fillRandom(uniformlyRandomWorkload);
var bestK, bestI:int=0;

var timer:Timer;
timer.start();

forall i in guidedDistributed(controlRange) do
{
  var result:real;
  var k:int=(uniformlyRandomWorkload[i] * n):int;
  var tempArray:[0..k] real=0.0;
  fillRandom(tempArray);
  for e in tempArray do
  {
    isPerfect(e:int);
    trialDivision(e:int);
  }
  //sort(tempArray);

  /*
  for j in fibo(v) do
    result = j;
  writeln("Iteration ", i, ": Calculated abs(", expoArray[i], " % ", n, ") = ",
          v, " and got fibo(", v, ") = ", result, ".");
  */

  /*
  for j in fibo(k) do
    result = j;

  for j in fact(k) do
    result = j;

  for j in sieveOfEratosthenes(k) do
    result = j;
  */

  //writeln("The prime factors of ", k, " are ", trialDivision(k), ".");

  /*
  for j in expoSeries(10, k) do
    result=j;
  writeln("e ** 10 = ", result, " at a = 0 with ", k, " iterations.");
  */

  /*
  if k > bestK then
  {
    bestK = k;
    bestI = i;
  }
  */

  /*
  for j in expoSeries(3,k) do
    result = j:int;
    writeln("expoArray [", i, "]: Calculated k = abs(", expoArray[i], " % ", n,
            ") = ", k, " and got e ** 3 = ", result, " with k iterations.");
  */

  //uniformlyRandomWorkload[i] = result;
}

timer.stop();
writeln("Time: ", timer.elapsed());
timer.clear();

writeln("uniformlyRandomWorkload[", bestI, "] = ",
        uniformlyRandomWorkload[bestI], " with size ", bestK,
        ".");
//checkCorrectness(uniformlyRandomWorkloadArray,controlRange);

/*
  Iterate over a range that maps to values that are mostly the same except for
  a handful of much larger values to throw off the balance.
*/

// Helpers.
proc largest(c)
{
  var result:real;
  for x in c do
  {
    if x > result then result = x;
  }
  return result;
}

iter fibo(n:int)
{
  // Yields the Fibonacci sequence from the zeroth number to the nth.
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
{
  assert(n >= 0, "n must be a nonnegative integer");
  // Yields the factorial sequence from zero factorial up to n factorial.
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

iter expoSeries(x:real,k:int=30):real
{
  /*
    Yields up to k successive refinements of the Taylor series (at a = 0) for
    the exponential function e ** x.
    https://en.wikipedia.org/wiki/Taylor_series
  */
  var current:real=0.0;
  for (n_factorial,n) in zip(fact(k),0..k)
  {
    current += (x ** n) / n_factorial;
    yield current;
  }
}

iter piFabriceBellard(k:int)
{
  /*
    Yields a pi approximation to n iterations using Fabrice Bellard's formula.
    https://en.wikipedia.org/wiki/Approximations_of_%CF%80#Efficient_methods
  */
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

iter piBBP(n:int)
{
  /*
    Yields a pi approximation to n iterations using Bailey, Borwein, and
    Plouffe's formula.
    https://en.wikipedia.org/wiki/Approximations_of_%CF%80#Efficient_methods
  */
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

iter sieveOfEratosthenes(n:int)
{
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

proc trialDivision(n:int):domain(int)        // def trialDivision(n):
{
  // Return an associative domain containing n's prime factors.
                                             // """Return a list of the prime factors for a natural number."""
  if n < 2                                   // if n < 2:
  then return {1..0};                        //   return []
  var x:int=n;                               // x = n # Need this only for Chapel.
  var primeFactors:domain(int);              // primeFactors = []
  writeln(x, "**0.5:int is ", (x**0.5):int);
  for p in sieveOfEratosthenes((x**0.5):int) // for p in prime_sieve(int(x**0.5)):
  {
    writeln("Checking ", p*p, " > ", x);
    if p*p > x then break;                   //   if p*p > x: break
    while x % p == 0 do                      //   while x % p == 0:
    {
      primeFactors += p;                     //     primeFactors.append(p)
      x = divfloorpos(x,p);                  //     x //= p
    }
  }
  if x > 1                                   // if x > 1:
  then primeFactors += x;                    //   primeFactors.append(x)

  return primeFactors;                       // return primeFactors
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

proc isHarmonicDivisor(n:int):bool
{
  /*
    A harmonic divisor number, or Ore number, is a positive integer whose
    divisors have a harmonic mean that is an integer.
    https://en.wikipedia.org/wiki/Harmonic_divisor_number
  */
  if n < 1 then return false;
  if n == 1 then return true;
  var numerator,denominator,harmonicMean:real;
  var divisorsN:domain(int)=divisors(n);
  numerator=divisorsN.size;
  for p in divisorsN do denominator += 1/(p:real);
  harmonicMean=numerator/denominator;
  /*
    TODO: We would like to do this here:

      return harmonicMean == round(harmonicMean)

    But, we cannot, because for n = 6, we get harmonicMean = 2.0 but
    ceil(harmonicMean) = 3.0. That is, the harmonic mean calculation includes
    some infinitesmial amount such that the above desired comparison
    expression fails even when it should succeed. We could use some kind of
    fraction representation, with algrbraic manipulation, to make this
    procedure work... but currently it does not.
  */
  return harmonicMean == round(harmonicMean);
}
