/*
 * Copyright 2004-2017 Cray Inc.
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

 /*
   This module contains iterators that can be used to distribute a `forall` loop
   for a range, domain, or array.

   Part of a 2017 Cray summer intern project by Sean I. Geronimo Anderson
   (sgeronimo@cray.com) as mentored by Ben Harshbarger (bharshbarg@cray.com).
 */
module DistributedItersSandbox
{
use DynamicIters,
    Time;

// Toggle debugging output and per-locale performance timing.
config param debugDistributedIters:bool = false;
config param timeDistributedIters:bool = false;

// Toggle writing system information.
config const infoDistributedIters:bool = false;

// Distributed Guided Iterator.
/*
  :arg c: The range (or domain) to iterate over. The range (domain) size must
    be greater than zero.
  :type c: `range(?)` or `domain`

  :arg numTasks: The number of tasks to use. Must be >= zero. If this argument
    has value 0, the iterator will use the value indicated by
    ``dataParTasksPerLocale``.
  :type numTasks: `int`

  :arg parDim: If ``c`` is a domain, then this specifies the dimension index
    to parallelize across. Must be positive, and must be at most the rank of
    the domain ``c``. Defaults to 1.
  :type parDim: `int`

  :arg minChunkSize: The smallest allowable chunk size. Must be at least one.
    Default is one.
  :type minChunkSize: `int`

  :arg coordinated: Have locale 0 coordinate task distribution only; disallow
    it from receiving work. (If true and multi-locale.)
  :type coordinated: `bool`

  :arg workerLocales: An array of locales over which to distribute the work.
    Defaults to Locales (all available locales).
  :type workerLocales: `[]locale`

  :yields: Indices in the range ``c``.

  This iterator is equivalent to a distributed version of the guided policy of
  OpenMP: Given an input range (domain) ``c``, each locale (except the calling
  locale, if coordinated is true) receives chunks of approximately
  exponentially decreasing size, until the remaining iterations reaches a
  minimum value, ``minChunkSize``, or there are no remaining iterations in
  ``c``. The chunk size is the number of unassigned iterations divided by the
  number of locales. Each locale then distributes sub-chunks as tasks, where
  each sub-chunk size is the number of unassigned local iterations divided by
  the number of tasks, ``numTasks``, and decreases approximately exponentially
  to 1. The splitting strategy is therefore adaptive.

  This iterator is available for serial and zippered contexts.
*/
// Serial version.
iter distributedGuided(c,
                       numTasks:int=0,
                       parDim:int=1,
                       minChunkSize:int=1,
                       coordinated:bool=false,
                       workerLocales=Locales)
{
  assert((isDomain(c) || isRange(c)), ("DistributedIters: Serial guided "
                                       + "iterator: must use a valid domain "
                                       + "or range"));

  if debugDistributedIters
  then writeln("DistributedIters: Serial guided iterator, working with ",
               (if isDomain(c) then "domain " else "range "), c);
  for i in c do yield i;
}

// Zippered leader.
pragma "no doc"
iter distributedGuided(param tag:iterKind,
                       c,
                       numTasks:int=0,
                       parDim:int=1,
                       minChunkSize:int=1,
                       coordinated:bool=false,
                       workerLocales=Locales)
where tag == iterKind.leader
{
  assert((isDomain(c) || isRange(c)), ("DistributedIters: Guided iterator "
                                       + "(leader): must use a valid domain "
                                       + "or range"));
  if isDomain(c) then
  {
    assert(c.rank > 0, ("DistributedIters: Guided iterator (leader): Must "
                        + "use a valid domain"));
    assert(parDim > 0, ("DistributedIters: Guided iterator (leader): parDim "
                        + "must be a positive integer"));
    assert(parDim <= c.rank, ("DistributedIters: Guided iterator (leader): "
                              + "parDim must be a dimension of the domain"));

    var parDimDim = c.dim(parDim);

    for t in distributedGuided(tag=iterKind.leader,
                               c=parDimDim,
                               numTasks=numTasks,
                               parDim=1,
                               minChunkSize=minChunkSize,
                               coordinated=coordinated,
                               workerLocales=workerLocales)
    {
      // Set the new range based on the tuple the guided 1-D iterator yields.
      var newRange = t(1);

      type cType = c.type;
      // Does the same thing as densify, but densify makes a stridable domain,
      // which mismatches here if c (and thus cType) is non-stridable.
      var tempDom : cType = computeZeroBasedDomain(c);

      // Rank-change slice the domain along parDim
      var tempTup = tempDom.dims();
      // Change the value of the parDim elem of the tuple to the new range
      tempTup(parDim) = newRange;

      yield tempTup;
    }
  }
  else // c is a range.
  {
    const iterCount = c.length;

    if iterCount == 0 then halt("DistributedIters: Guided iterator (leader): ",
                                "the range is empty");

    type cType = c.type;
    const denseRange:cType = densify(c,c);

    if iterCount == 1
       || numTasks == 1 && numLocales == 1
    then
    {
      if debugDistributedIters
      then writeln("DistributedIters: Guided iterator (leader): serial ",
                   "execution due to insufficient work or compute resources");
      yield (denseRange,);
    }
    else
    {
      const numWorkerLocales = workerLocales.size;
      const denseRangeHigh:int = denseRange.high;
      const masterLocale = here.locale;

      const potentialWorkerLocales =
        [L in workerLocales] if numLocales == 1
                                || !coordinated
                                || L != masterLocale
                             then L;
      /*
        It's not sensible to use a single locale besides masterLocale, so use
        potentialWorkerLocales only if it's larger than one locale.
      */
      const actualWorkerLocales = if potentialWorkerLocales.size > 1
                                  then potentialWorkerLocales
                                  else [masterLocale];
      const numActualWorkerLocales = actualWorkerLocales.size;

      // The guided iterator stage (determines next subrange index and size).
      var meitneriumIndex:atomic int;

      if infoDistributedIters then
      {
        const actualWorkerLocaleIds = [L in actualWorkerLocales] L.id:string;
        const actualWorkerLocaleIdsSorted = actualWorkerLocaleIds.sorted();
        writeln("DistributedIters: guidedDistributed:");
        writeln("  coordinated = ", coordinated);
        writeln("  numLocales = ", numLocales);
        writeln("  numWorkerLocales = ", numWorkerLocales);
        writeln("  numActualWorkerLocales = ", numActualWorkerLocales);
        writeln("  masterLocale.id = ", masterLocale.id);
        writeln("  actualWorkerLocaleIds = [ ",
                ", ".join(actualWorkerLocaleIdsSorted),
                " ]");
      }

      var localeTimes:[0..#numLocales]real;
      var totalTime:Timer;
      if timeDistributedIters then totalTime.start();

      coforall L in actualWorkerLocales
      with (ref meitneriumIndex, ref localeTimes) do
      on L do
      {
        var localeTime:Timer;
        if timeDistributedIters then localeTime.start();

        var localeStage:int = meitneriumIndex.fetchAdd(1);
        var localeRange:cType = guidedSubrange(denseRange,
                                               numActualWorkerLocales,
                                               localeStage);
        while localeRange.high <= denseRangeHigh do
        {
          const denseLocaleRange:cType = densify(localeRange, localeRange);
          for denseTaskRangeTuple in DynamicIters.guided(tag=iterKind.leader,
                                                         localeRange,
                                                         numTasks) do
          {
            const taskRange:cType = unDensify(denseTaskRangeTuple(1),
                                              localeRange);
            if debugDistributedIters
            then writeln("DistributedIters: Guided iterator (leader): ",
                         here.locale, ": yielding ", unDensify(taskRange,c),
                         " (", taskRange.length,
                         "/", localeRange.length,
                         " locale-owned of ", iterCount,
                         " total) as ", taskRange);
            yield (taskRange,);
          }

          localeStage = meitneriumIndex.fetchAdd(1);
          localeRange = guidedSubrange(denseRange,
                                       numActualWorkerLocales,
                                       localeStage);
        }

        if timeDistributedIters then
        {
          localeTime.stop();
          localeTimes[here.id] = localeTime.elapsed();
        }
      }

      if timeDistributedIters then
      {
        totalTime.stop();
        writeTimeStatistics(totalTime.elapsed(), localeTimes, coordinated);
      }
    }
  }
}

// Zippered follower.
pragma "no doc"
iter distributedGuided(param tag:iterKind,
                       c,
                       numTasks:int,
                       parDim:int=1,
                       minChunkSize:int,
                       coordinated:bool,
                       workerLocales=Locales,
                       followThis)
where tag == iterKind.follower
{
  assert((isDomain(c) || isRange(c)), ("DistributedIters: Guided iterator "
                                       + "(follower): Must use a valid "
                                       + "domain or range"));

  const current = if isDomain(c)
                  then c._value.these(tag=iterKind.follower,
                                      followThis=followThis)
                  else unDensify(followThis(1), c);

  if debugDistributedIters
  then writeln("DistributedIters: Guided iterator (follower): ", here.locale,
               ": received ",
               if isDomain(c) then "domain " else "range ",
               followThis, " (", current.size,
               "/", c.size, "); shifting to ", current);

  for i in current do yield i;
}

/*
  Helpers.
*/

// Guided subrange calculation.
/*
  :arg c: The range from which to retrieve a guided subrange.
  :type c: `range(?)`

  :arg workerCount: The number of workers (locales, tasks) to assume are
    working on ``c``. This (along with stage) determines the subrange length.
  :type workerCount: `int`

  :arg stage: The number of guided subranges to skip before returning a
    guided subrange.
  :type stage: `int`

  :arg minChunkSize: The smallest allowable chunk size. Must be >= 1.
    Defaults to 1.
  :type minChunkSize: `int`

  :returns: A subrange of ``c``.

  This function takes a range, a worker count, and a stage, and simulates
  performing OpenMP's guided schedule on the range with the given worker
  count until reaching the given stage. It then returns the subrange that the
  guided schedule would have produced at that point. The simulation overhead
  is insignificant.
*/
private proc guidedSubrange(c:range(?),
                            workerCount:int,
                            stage:int,
                            minChunkSize:int=1)
{
  assert(workerCount > 0, ("DistributedIters: guidedSubrange: "
                           + "'workerCount' must be positive"));
  const cLength = c.length;
  var low:int = c.low;
  var chunkSize:int = (cLength / workerCount);
  var remainder:int = (cLength - chunkSize);
  for unused in (1..#stage) do
  {
    low += chunkSize;
    chunkSize = (remainder / workerCount);
    chunkSize = if (chunkSize >= minChunkSize)
                then chunkSize
                else minChunkSize;
    remainder -= chunkSize;
  }
  const subrange:c.type = (low..#chunkSize);
  return subrange;
}

// Per-locale time statistics.
/*
  :arg wallTime: The wall time statistic.
  :type wallTime: `real`

  :arg localeTimes: Time statistic per locale.
  :type localeTimes: `[]real`

  :arg coordinated: Whether the time statistics are from coordinated mode.
  :type coordinated: `bool`

  This function takes a real wall time (only for writing out), a per-locale
  real time array, and a coordinated boolean, and writes out a formatted
  performance timing summary: Total time for each locale, and locale time
*/
proc writeTimeStatistics(wallTime:real,
                         localeTimes:[]real,
                         coordinated:bool)
{
  const low:int = if coordinated && (numLocales > 1)
                  then 1
                  else 0;
  const nLocales:int = if coordinated && (numLocales > 1)
                       then (numLocales - 1)
                       else numLocales;
  var localeMeanTime,localeStdDev,localeTotalTime:real;
  var localeTimesFormatted:string;

  const localeRange:range = low..#nLocales;
  for i in localeRange do
  {
    const localeTime = localeTimes[i];
    localeTotalTime += localeTime;
    localeTimesFormatted += (i + ": " + localeTime);
    localeTimesFormatted += if i == localeRange.high
                            then ""
                            else ", ";
  }
  localeMeanTime = (localeTotalTime / nLocales);

  for i in localeRange
  do localeStdDev += ((localeTimes[i] - localeMeanTime) ** 2);
  localeStdDev = ((localeStdDev / nLocales) ** (1.0 / 2.0));

  writeln("DistributedIters: total time by locale: ", localeTimesFormatted);
  writeln("DistributedIters: wall time: ", wallTime);
  writeln("DistributedIters: locale time (total, mean, stddev): (",
          localeTotalTime, ", ",
          localeMeanTime, ", ",
          localeStdDev, ").");
}

} // End of module.

// Scratch.



/* // Begin separate version.

// Serial iterator, domain version.
iter distributedGuided(c:domain,
                       numTasks:int=0,
                       parDim:int=1,
                       minChunkSize:int=1,
                       coordinated:bool=false,
                       workerLocales=Locales)
{
  if debugDistributedIters
  then writeln("Serial guided iterator, working with domain ", c);

  for i in c do yield i;
}

// Serial iterator, range version.
iter distributedGuided(c:range(?),
                       numTasks:int=0,
                       parDim:int=1,
                       minChunkSize:int=1,
                       coordinated:bool=false,
                       workerLocales=Locales)
{
  if debugDistributedIters
  then writeln("Serial guided iterator, working with range ", c);

  for i in c do yield i;
}

// Zippered leader, domain version.
pragma "no doc"
iter distributedGuided(param tag:iterKind,
                       c,
                       numTasks:int=0,
                       parDim:int=1,
                       minChunkSize:int=1,
                       coordinated:bool=false,
                       workerLocales=Locales)
where tag == iterKind.leader
{

  assert(c.rank > 0, "Must use a valid domain");
  assert(parDim > 0, "parDim must be a positive integer");
  assert(parDim <= c.rank, "parDim must be a dimension of the domain");

  var parDimDim = c.dim(parDim);

  for t in distributedGuided(tag=iterKind.leader,
                             c=parDimDim,
                             numTasks=numTasks,
                             parDim=1,
                             minChunkSize=minChunkSize,
                             coordinated=coordinated,
                             workerLocales=workerLocales)
  {
    // Set the new range based on the tuple the guided 1-D iterator yields.
    var newRange = t(1);

    type cType = c.type;
    // Does the same thing as densify, but densify makes a stridable domain,
    // which mismatches here if c (and thus cType) is non-stridable.
    var tempDom : cType = computeZeroBasedDomain(c);

    // Rank-change slice the domain along parDim
    var tempTup = tempDom.dims();
    // Change the value of the parDim elem of the tuple to the new range
    tempTup(parDim) = newRange;

    yield tempTup;
  }
}

// Zippered leader, range version.
pragma "no doc"
iter distributedGuided(param tag:iterKind,
                       c:range(?),
                       numTasks:int=0,
                       parDim:int=1,
                       minChunkSize:int=1,
                       coordinated:bool=false,
                       workerLocales=Locales)
where tag == iterKind.leader
{
  const iterCount = c.length;

  if iterCount == 0 then halt("The range is empty");

  type cType = c.type;
  const denseRange:cType = densify(c,c);

  if iterCount == 1
     || numTasks == 1 && numLocales == 1
  then
  {
    if debugDistributedIters
    then writeln("Distributed guided iterator: serial execution due to ",
                 "insufficient work or compute resources");
    yield (denseRange,);
  }
  else
  {
    const numWorkerLocales = workerLocales.size;
    const denseRangeHigh:int = denseRange.high;
    const masterLocale = here.locale;
    const nLocales = if coordinated && numWorkerLocales > 1
                     then (numWorkerLocales - 1)
                     else numWorkerLocales;
    var meitneriumIndex:atomic int;

    var localeTimes:[0..#numLocales]real = 0.0; // #numLocales is the safest.
    var totalTime:Timer;
    if timeDistributedIters then totalTime.start();

    coforall L in workerLocales
    with (ref meitneriumIndex, ref localeTimes) do
    on L do
    {
      if numLocales == 1
         || !coordinated
         || L != masterLocale // Necessarily, coordinated == true
      then
      {
        var localeTime:Timer;
        if timeDistributedIters then localeTime.start();

        var localeStage:int = meitneriumIndex.fetchAdd(1);
        var localeRange:cType = guidedSubrange(denseRange,
                                               nLocales,
                                               localeStage);
        while localeRange.high <= denseRangeHigh do
        {
          const denseLocaleRange:cType = densify(localeRange, localeRange);
          for denseTaskRangeTuple in DynamicIters.guided(tag=iterKind.leader,
                                                         localeRange,
                                                         numTasks) do
          {
            const taskRange:cType = unDensify(denseTaskRangeTuple(1),
                                              localeRange);
            if debugDistributedIters then
            {
              writeln("Distributed guided iterator (leader): ", here.locale,
                      ": yielding ", unDensify(taskRange,c),
                      " (", taskRange.length,
                      "/", localeRange.length,
                      " locale-owned of ", iterCount,
                      " total) as ", taskRange);
            }

            yield (taskRange,);
          }

          localeStage = meitneriumIndex.fetchAdd(1);
          localeRange = guidedSubrange(denseRange, nLocales, localeStage);
        }

        if timeDistributedIters then
        {
          localeTime.stop();
          localeTimes[here.id] = localeTime.elapsed();
        }
      }
    }
    if timeDistributedIters then
    {
      totalTime.stop();
      writeTimeStatistics(totalTime.elapsed(), localeTimes, coordinated);
    }
  }
}

// Zippered follower, domain version.
pragma "no doc"
iter distributedGuided(param tag:iterKind,
                       c:domain,
                       numTasks:int,
                       parDim:int=1,
                       minChunkSize:int,
                       coordinated:bool,
                       workerLocales=Locales,
                       followThis)
where tag == iterKind.follower
{
  const current = c._value.these(tag=iterKind.follower, followThis=followThis);

  if debugDistributedIters
  then writeln("Distributed guided iterator (follower): ", here.locale, ": ",
               "received domain ", followThis, " (", current.size,
               "/", c.size, "); shifting to ", current);

  for i in current do yield i;
}

// Zippered follower, range version.
pragma "no doc"
iter distributedGuided(param tag:iterKind,
                       c:range(?),
                       numTasks:int,
                       parDim:int=1,
                       minChunkSize:int,
                       coordinated:bool,
                       workerLocales=Locales,
                       followThis)
where tag == iterKind.follower
{
  const current = unDensify(followThis(1), c);

  if debugDistributedIters
  then writeln("Distributed guided iterator (follower): ", here.locale, ": ",
               "received range ", followThis, " (", current.size,
               "/", c.size, "); shifting to ", current);

  for i in current do yield i;
}

*/ // End separate version.







/*
// Standalone version.
iter guided(param tag:iterKind,
            c:range(?),
            numTasks:int=0,
            minChunkSize:int=1,
            coordinated:bool=false)
where tag == iterKind.standalone
{
  if debugDistributedIters
  then writeln("Standalone guided iterator, working with range ", c);

  for i in c do yield i;
}
*/






/*
// Valid input types.
enum inputTypeEnum
{
  Range,
  Domain,
  Array
};
*/

// Distributed Iterator.
/*
  :arg c: The range (or domain or array) to iterate over. The length of the
          range (domain, array) must be greater than zero.
  :type c: `range(?)` (`domain`, `array`)

  :yields: Indices in the range (domain, array) ``c``.

  Given an input range (domain, array) ``c``, yields successive contiguous
  subsets of size ``chunkSize`` from ``c`` (or the remainder of ``c`` if
  smaller than ``chunkSize``).
*/
// Serial version.
/*
iter distributed(c,
                 numTasks:int=0,
                 parDim:int=1)
{
  var inputType:inputTypeEnum;
  var inputTypeStr:string;
  populateInputTypeInfo(c, inputType, inputTypeStr);

  if debugDistributedIters then
  {
    var inputVal = if isArray(c)
                   then c.localSubdomain()
                   else c;
    writeln("Distributed iterator: serial, working on ",
            inputTypeStr, ": ", inputVal);
  }

  const localC:c.type=if isArray(c)
                      then c.localSubdomain()
                      else c;

  if isArray(c)
  {
    writeln("Local subdomains are:");
    for d in c.localSubdomains()
    {
      writeln(d);
    }
  }

  for i in localC
  {
    //write(i, " ");
    yield i;
  }
  //writeln();

  //for i in c do yield i;
}
*/

/*
// Zippered leader.
pragma "no doc"
iter distributed(param tag:iterKind,
                 c,
                 numTasks:int=0,
                 parDim:int=1)
where tag == iterKind.leader
{
  var inputType:inputTypeEnum;
  var inputTypeStr:string;
  populateInputTypeInfo(c, inputType, inputTypeStr);

  // Iterator.
  // Caller's responsibility to use a valid domain.
  assert(c.rank > 0, "Must use a valid domain");

  // Caller's responsibility to use a valid parDim.
  assert(parDim <= c.rank, "parDim must be a dimension of the domain");
  assert(parDim > 0, "parDim must be a positive integer");

  var parDimDim = c.dim(parDim);

  for i in guided(tag=iterKind.leader, parDimDim, numTasks)
  {
    // Set the new range based on the tuple the guided 1-D iterator yields.
    var newRange = i(1);

    type cType = c.type;
    // Regularize. "We can't use densify because it makes a stridable domain,
    // which mismatches here if c (and thus cType) is non-stridable."
    var tempDom : cType = computeZeroBasedDomain(c);

    // "Rank-change slice the domain along parDim"
    var tempTup = tempDom.dims();
    // Change the value of the parDim elem of the tuple to the new range
    tempTup(parDim) = newRange;

    yield tempTup;
  }
}
*/

/*
// Zippered follower.
pragma "no doc"
iter distributed(param tag:iterKind,
                 c,
                 numTasks:int,
                 parDim:int,
                 followThis)
where tag == iterKind.follower
{
  var inputType:inputTypeEnum;
  var inputTypeStr:string;
  populateInputTypeInfo(c, inputType, inputTypeStr);

  if debugDistributedIters then
  {
    var inputVal = if isArray(c)
                   then "(array contents hidden)"
                   else c;
    writeln("Distributed Iterator: Follower received ",
            inputTypeStr, ": ", inputVal);
  }

  select true
  {
    when
  }
}
*/

/*
// Helpers.
inline proc populateInputTypeInfo(c, ref inputType, ref inputTypeStr)
{
  select true
  {
    when isRange(c)
    {
      inputType = inputTypeEnum.Range;
      inputTypeStr = "range";
    }
    when isDomain(c)
    {
      inputType = inputTypeEnum.Domain;
      inputTypeStr = "domain";
    }
    when isArray(c)
    {
      inputType = inputTypeEnum.Array;
      inputTypeStr = "array";
    }
    otherwise compilerError("DistributedIters: expected range, domain, or "
                            + "array",
                            1);
  }
}
*/







// Valid input types.
/*
enum inputTypeEnum
{
  Range,
  Domain,
  Array
};
*/

// Distributed Guided Iterator.
/*
  :arg c: The range (or domain or array) to iterate over. The range (domain,
    array) must have size greater than zero.
  :type c: `range(?)` (`domain`, `array`)

  :arg numTasks: The number of tasks to use. Must be >= zero. If this argument
    has value 0, the iterator will use the value indicated by
    ``dataParTasksPerLocale``.
  :type numTasks: `int`

  :arg parDim: If ``c`` is a domain, this specifies the index of the dimension
    to parallelize across. Must be > 0, and must be <= the rank of the domain
    ``c``. Defaults to 1.
  :type parDim: `int`

  :arg minChunkSize: The smallest allowable chunk size. Must be >= one.
    Defaults to 1.
  :type minChunkSize: `int`

  :arg coordinated: Have locale 0 coordinate task distribution only; disallow
    it from receiving work. (If true and multi-locale.)
  :type coordinated: `bool`

  :yields: Indices in the range (domain, array) ``c``.

  This iterator is equivalent to a distributed version of the guided policy of
  OpenMP: Given an input range ``c``, each locale (except the calling locale)
  receives chunks of approximately exponentially decreasing size, until the
  remaining iterations reaches a minimum value, ``minChunkSize``, or there are
  no remaining iterations in ``c``. The chunk size is the number of unassigned
  iterations divided by the number of locales. Each locale then distributes
  sub-chunks as tasks, where each sub-chunk size is the number of unassigned
  local iterations divided by the number of tasks, ``numTasks``, and decreases
  approximately exponentially to 1. The splitting strategy is therefore
  adaptive.

  This iterator is available for serial and zippered contexts.
*/
// Serial version.
/*
iter distributedGuided(c,
                       numTasks:int=0,
                       parDim:int=1,
                       minChunkSize:int=1,
                       coordinated:bool=false,
                       workerLocales=Locales)
{
  // Ensure ``c`` is an array, domain, or range.
  const cValidatedType:ValidatedType = validateType(c);

  if debugDistributedIters
  then writeln("DistributedIters: Distributed guided iterator (serial): ",
               "working with ", cValidatedType);

  for i in c do yield i;
}
*/

/*
  Helpers.
*/

/*
// Valid input types.
enum ValidatedType
{
  Range,
  Domain,
  Array
};

proc validateType(c)
{
  var cValidatedType:ValidatedType;
  select true
  {
    when isRange(c) do cValidatedType = ValidatedType.Range;
    when isDomain(c) do cValidatedType = ValidatedType.Domain;
    when isArray(c) do cValidatedType = ValidatedType.Array;
    otherwise compilerError("DistributedIters: expected range, domain, or "
                            + "array",
                            1);
  }
  return cValidatedType;
}
*/



/* This is a work-in-progress. */
/*
// Zippered leader.
pragma "no doc"
iter distributedGuided(param tag:iterKind,
                       c,
                       numTasks:int=0,
                       minChunkSize:int=1,
                       parDim:int=1)
where tag == iterKind.leader
{
  var inputType:inputTypeEnum;
  var inputTypeStr:string;
  populateInputTypeInfo(c, inputType, inputTypeStr);

  // Iterator.
  // Caller's responsibility to use a valid domain.
  assert(c.rank > 0, "Must use a valid domain");

  // Caller's responsibility to use a valid parDim.
  assert(parDim <= c.rank, "parDim must be a dimension of the domain");
  assert(parDim > 0, "parDim must be a positive integer");

  var parDimDim = c.dim(parDim);

  for i in guided(tag=iterKind.leader, parDimDim, numTasks)
  {
    // Set the new range based on the tuple the guided 1-D iterator yields.
    var newRange = i(1);

    type cType = c.type;
    // Regularize. "We can't use densify because it makes a stridable domain,
    // which mismatches here if c (and thus cType) is non-stridable."
    var tempDom : cType = computeZeroBasedDomain(c);

    // "Rank-change slice the domain along parDim"
    var tempTup = tempDom.dims();
    // Change the value of the parDim elem of the tuple to the new range
    tempTup(parDim) = newRange;

    yield tempTup;
  }
}
*/





/*
// Zippered follower.
pragma "no doc"
iter distributedGuided(param tag:iterKind,
                       c,
                       numTasks:int,
                       parDim:int,
                       minChunkSize:int=1,
                       coordinated:bool=false,
                       followThis)
where tag == iterKind.follower
{
  const localC = if isArray(c)
                 then c.localSubdomain()
                 else c;
  const cValidatedType:ValidatedType = validateType(c);

  select cValidatedType
  {
    when ValidatedType.Range
    when ValidatedType.Domain
    when ValidatedType.Array
  }

  if debugDistributedIters
  then writeln("DistributedIters: Distributed guided iterator (follower): ",
               cValidatedType, ": ", here.locale, ": ",
               "received range ", followThis,
               " (", current.length, "/", c.length, ")",
               "; shifting to ", current);

}
pragma "no doc"
iter distributedGuided(param tag:iterKind,
                       c:range(?),
                       numTasks:int,
                       minChunkSize:int=1,
                       coordinated:bool=false,
                       followThis)
where tag == iterKind.follower
{
  const current:c.type=unDensify(followThis(1),c);

  if debugDistributedIters
  then writeln("Distributed guided iterator (follower): ", here.locale, ": ",
               "received range ", followThis,
               " (", current.length, "/", c.length, ")",
               "; shifting to ", current);

  for i in current do yield i;
}
*/
