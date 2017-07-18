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
  This module contains several iterators that can be used to drive a `forall`
  loop by distributing iterations for a range, domain, or array.
*/
module DistributedItersSandbox
{
use DynamicIters,
    Time;

// Toggle debugging output.
config param debugDistributedIters:bool=true;

if debugDistributedIters
then writeln("DistributedIters: Running on locale ", here.id, " of ",
             numLocales, " total");

// Valid input types.
enum inputTypeEnum
{
  Range,
  Domain,
  Array
};

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


// Guided Distributed Iterator.
/*
  :arg c: The range to iterate over. The length of the range must be greater
    than zero.
  :type c: `range(?)`

  :arg numTasks: The number of tasks to use. Must be >= zero. If this argument
    has value 0, the iterator will use the value indicated by
    ``dataParTasksPerLocale``.
  :type numTasks: `int`

  :arg minChunkSize: The smallest allowable chunk size. Must be >= one. Default
    is one.
  :type minChunkSize: `int`

  :arg coordinated: Have locale 0 coordinate task distribution only; disallow
    it from receiving work. (If true and multi-locale.)
  :type coordinated: `bool`

  :yields: Indices in the range ``c``.

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
iter guidedDistributed(c:range(?),
                       numTasks:int=0,
                       minChunkSize:int=1,
                       coordinated:bool=false)
{
  if debugDistributedIters
  then writeln("Serial guided iterator, working with range ", c);

  for i in c do yield i;
}

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

// Zippered version.
pragma "no doc"
iter guidedDistributed(param tag:iterKind,
                       c:range(?),
                       numTasks:int=0,
                       minChunkSize:int=1,
                       coordinated:bool=false)
where tag == iterKind.leader
{
  const iterCount=c.length;

  if iterCount == 0 then halt("The range is empty");

  type cType=c.type;
  const denseRange:cType=densify(c,c);

  if iterCount == 1 || numTasks == 1 && numLocales == 1
  then
  {
    if debugDistributedIters
    then writeln("Distributed guided iterator: serial execution due to ",
                 "insufficient work or compute resources");
    yield (denseRange,);
  }
  else
  {
    const denseRangeHigh:int = denseRange.high;
    const masterLocale = here.locale;
    const nLocales = if coordinated && numLocales > 1
                     then numLocales-1
                     else numLocales;
    var meitneriumIndex:atomic int;
    var localeTimes:[0..#numLocales]real = 0.0;
    var totalTime:Timer;

    totalTime.start();

    if debugDistributedIters
    then writeln("iterCount = ", iterCount,
                 ", nLocales = ", nLocales);

    coforall L in Locales
    with (ref meitneriumIndex, ref localeTimes) do
    on L do
    {
      if numLocales == 1
         || !coordinated
         || L != masterLocale // coordinated == true
      then
      {
        var localeTime:Timer;
        localeTime.start();

        var localeStage:int = meitneriumIndex.fetchAdd(1);
        var localeRange:cType = guidedSubrange(denseRange,
                                               nLocales,
                                               localeStage);
        while localeRange.high <= denseRangeHigh do
        {
          const denseLocaleRange:cType = densify(localeRange, localeRange);
          for denseTaskRangeTuple in DynamicIters.guided(tag=iterKind.leader,
                                                    localeRange,
                                                    numTasks)
          {
            const taskRange:cType = unDensify(denseTaskRangeTuple(1),
                                              localeRange);
            if debugDistributedIters
            {
              writeln("Distributed guided iterator (leader): ",
                      here.locale, ": yielding ",
                      unDensify(taskRange,c),
                      " (", taskRange.length,
                      "/", localeRange.length,
                      " locale-owned of ", iterCount, " total)",
                      " as ", taskRange);
            }
            yield (taskRange,);
          }

          localeStage = meitneriumIndex.fetchAdd(1);
          localeRange = guidedSubrange(denseRange, nLocales, localeStage);
        }
        localeTime.stop();
        localeTimes[here.id] = localeTime.elapsed();
      }
    }
    totalTime.stop();
    if true then writeTimeStatistics(totalTime.elapsed(),
                                     localeTimes,
                                     coordinated);
  }
}
pragma "no doc"
iter guidedDistributed(param tag:iterKind,
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

// Guided Distributed Domain Iterator.
/*
  :arg c: The domain to iterate over. The domain rank must be greater than
    zero.
  :type c: `domain`

  :arg numTasks: The number of tasks to use. Must be >= zero. If this argument
    has value 0, the iterator will use the value indicated by
    ``dataParTasksPerLocale``.
  :type numTasks: `int`

  :arg parDim: The index of the dimension to parallelize across. Must be > 0,
    and must be <= the rank of the domain ``c``. Defaults to 1.
  :type parDim: `int`

  :arg minChunkSize: The smallest allowable chunk size. Must be >= one.
    Defaults to 1.
  :type minChunkSize: `int`

  :arg coordinated: Have locale 0 coordinate task distribution only; disallow
    it from receiving work. (If true and multi-locale.)
  :type coordinated: `bool`

  :yields: Indices in the domain ``c``.

  This iterator is equivalent to a distributed version of the guided policy of
  OpenMP: Given an input domain ``c``, each locale (except the calling locale)
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
iter guidedDistributed(c:domain,
                       numTasks:int=0,
                       parDim:int=1,
                       minChunkSize:int=1,
                       coordinated:bool=false)
{
  if debugDistributedIters
  then writeln("DistributedIters: Distributed guided domain iterator ",
               "(serial): ", here.locale, ": working with domain ", c);
  for i in c do yield i;
}

// Zippered leader.
pragma "no doc"
iter guidedDistributed(param tag:iterKind,
                       c:domain,
                       numTasks:int=0,
                       parDim:int=1,
                       minChunkSize:int=1,
                       coordinated:bool=false)
where tag == iterKind.leader
{
  assert(c.rank > 0, "Must use a valid domain");
  assert(parDim <= c.rank, "parDim must be a dimension of the domain");
  assert(parDim > 0, "parDim must be a positive integer");

  var parDimDim = c.dim(parDim);

  for i in guidedDistributed(tag=iterKind.leader,
                             c=parDimDim,
                             numTasks=numTasks,
                             minChunkSize=minChunkSize,
                             coordinated=coordinated)
  {
    // Set the new range based on the tuple the guided 1-D iterator yields.
    var newRange = i(1);

    type cType = c.type;
    // Does the same thing as densify, but densify makes a stridable domain,
    // which mismatches here if c (and thus cType) is non-stridable.
    var tempDom : cType = computeZeroBasedDomain(c);

    // Rank-change slice the domain along parDim
    var tempTup = tempDom.dims();
    // Change the value of the parDim elem of the tuple to the new range
    tempTup(parDim) = newRange;

    /* // TODO: Do we even need this?
    writeln("Distributed guided iterator (leader): ",
            here.locale, ": yielding ",
            unDensify(taskRange,c),
            " (", taskRange.length,
            "/", localeRange.length,
            " locale-owned of ", iterCount, " total)",
            " as ", taskRange);
    */

    yield tempTup;
  }
}

// Zippered follower.
pragma "no doc"
iter guidedDistributed(param tag:iterKind,
                       c:domain,
                       numTasks:int,
                       parDim:int=1,
                       minChunkSize:int,
                       coordinated:bool,
                       followThis)
where tag == iterKind.follower
{
  const current = c._value.these(tag=iterKind.follower, followThis=followThis);

  /* // TODO: Try this.
  if debugDistributedIters
  then writeln("DistributedIters: Distributed guided domain iterator ",
               "(follower): ", here.locale, ": ",
               "received domain ", followThis,
               " (", current.length, "/", c.length, ")",
               "; shifting to ", current);
  */

  for i in current do yield i;
}









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

/* This is a work-in-progress.
// Serial version.
iter distributedGuided(c,
                       numTasks:int=0,
                       parDim:int=1,
                       minChunkSize:int=1,
                       coordinated:bool=false)
{
  const cValidatedType:ValidatedType = validateType(c);

  const isArrayC:bool = isArray(c);
  const isRangeC:bool = isRange(c);
  const localC = if isRangeC
                 then {c}:domain(1)
                 else c.localSubdomain();

  const cValidatedType:ValidatedType = validateType(c);


  if debugDistributedIters
  then writeln("DistributedIters: Distributed guided iterator (serial): ",
               cValidatedType);

  if isArrayC
  then for i in localC do yield c[i];
  else for i in localC do yield i;
}

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
iter guidedDistributed(param tag:iterKind,
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



// Helpers.

private proc defaultNumTasks(nTasks:int)
{
  var dnTasks=nTasks;
  if nTasks == 0
  then
  {
    if dataParTasksPerLocale == 0
    then dnTasks=here.maxTaskPar;
    else dnTasks=dataParTasksPerLocale;
  }
  else if nTasks < 0 then halt("'numTasks' is negative");
  return dnTasks;
}

private proc guidedSubrange(c:range(?),
                            workerCount:int,
                            stage:int,
                            minChunkSize:int=1)
/*
  :arg c: The range from which to retrieve a guided subrange.
  :type c: `range(?)`

  :arg workerCount: The number of workers (locales, tasks) to assume are
                    working on ``c``. This (along with stage) determines the
                    subrange length.
  :type workerCount: `int`

  :arg stage: The number of guided subranges to skip before returning a guided
              subrange.
  :type stage: `int`

  :arg minChunkSize: The smallest allowable chunk size. Must be >= 1. Defaults
    to 1.
  :type minChunkSize: `int`

  :returns: A subrange of ``c``.

  This function takes a range, a worker count, and a stage, and simulates
  performing OpenMP's guided schedule on the range with the given worker count
  until reaching the given stage. It then returns the subrange that the guided
  schedule would have produced at that point. The simulation overhead is
  insignificant.
*/
{
  assert(workerCount > 0, "'workerCount' must be positive");
  const cLength = c.length;
  var low:int = c.low;
  var chunkSize:int = cLength / workerCount;
  var remainder:int = cLength - chunkSize;
  for unused in 1..#stage do
  {
    low += chunkSize;
    chunkSize = remainder / workerCount;
    chunkSize = if chunkSize >= minChunkSize
                then chunkSize
                else minChunkSize;
    remainder -= chunkSize;
  }
  const subrange:c.type = low..#chunkSize;
  return subrange;
}

proc writeTimeStatistics(totalTime, localeTimes:[], coordinated)
{
  const low:int = if coordinated && (numLocales > 1)
                  then 1
                  else 0;
  const nLocales:int = if coordinated && (numLocales > 1)
                       then (numLocales-1)
                       else numLocales;
  var localeMeanTime,localeStdDev,localeTotalTime:real;
  var localeTimesFormatted:string = "";

  const localeRange:range = low..#nLocales;
  for i in localeRange do
  {
    const localeTime = localeTimes[i];
    localeTotalTime += localeTime;
    localeTimesFormatted += (i + ": " + localeTime + (if i == localeRange.high
                                                      then ""
                                                      else ", "));
  }
  localeMeanTime = (localeTotalTime/nLocales);

  for i in low..#nLocales do
    localeStdDev += ((localeTimes[i]-localeMeanTime)**2);
  localeStdDev = ((localeStdDev/nLocales)**(1.0/2.0));

  writeln("DistributedIters: total time by locale: ", localeTimesFormatted);
  writeln("DistributedIters: locale time (total, mean, stddev): (",
          totalTime, ", ",
          localeMeanTime, ", ",
          localeStdDev, ").");
}

} // End of module.
