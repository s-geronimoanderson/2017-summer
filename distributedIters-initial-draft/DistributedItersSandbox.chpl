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
use DynamicIters;

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
    otherwise compilerError("distributed: expected range, domain, or array",
                            1);
  }
}


// Guided Distributed Iterator.
/*
  :arg c: The range to iterate over. The length of the range must be greater
          than zero.
  :type c: `range(?)`

  :arg numTasks: The number of tasks to use. Must be >= zero. If this argument
                 has the value 0, the iterator will use the value indicated by
                 ``dataParTasksPerLocale``.
  :type numTasks: `int`

  :arg minChunkSize: The smallest allowable chunk size. Must be >= zero. If
                     this argument has the value 0, the iterator will use the
                     input range length divided by ``numLocales``.
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
                       coordinated:bool=false)
where tag == iterKind.leader
{
  const iterCount=c.length;
  if iterCount == 0 then halt("The range is empty");

  type cType=c.type;
  var remain:cType=densify(c,c);

  if iterCount == 1 || numTasks == 1 && numLocales == 1
  then
  {
    if debugDistributedIters
    then writeln("Distributed guided iterator: serial execution due to ",
                 "insufficient work or compute resources");
    yield (remain,);
  }
  else
  {
    const nLocales=if coordinated && numLocales > 1
                   then numLocales-1
                   else numLocales;
    const masterLocale=here.locale;
    var meitneriumIndex:atomic int;

    const scaleFactor:real=iterCount/nLocales;
    const commonRatio:real=if nLocales > 1
                           then (1-1/nLocales)
                           else 1;
    const finalIndex:int=if nLocales > 1
                         then (1+log(nLocales)/log(commonRatio)):int
                         else 1;

    coforall L in Locales
    with (ref meitneriumIndex) do
    on L do
    {
      if numLocales == 1
         || ! coordinated
         || L != masterLocale // coordinated == true
      then
      {
        var cachedIndex:int=meitneriumIndex.fetchAdd(1);
        var currentLocalIndex,nextLocalIndex:int;

        while cachedIndex < finalIndex do
        {
          writeln("cachedIndex = ", cachedIndex,
                  ", finalIndex = ", finalIndex,
                  ", iterCount = ", iterCount);

          currentLocalIndex=(scaleFactor * (commonRatio ** cachedIndex)):int;
          nextLocalIndex=(scaleFactor * (commonRatio ** (cachedIndex+1))):int;
          /*
            If the cached index is not zero, then we can use the closed-form
            calculation to get the local index. Otherwise, index 0 is a special
            case (it's zero).
          */
          currentLocalIndex=if cachedIndex > 0
                            then currentLocalIndex
                            else 0;

          const current:cType=currentLocalIndex..(nextLocalIndex-1);

          writeln("commonRatio = ", commonRatio,
                  ", scaleFactor = ", scaleFactor);

          if debugDistributedIters
          then writeln("Distributed guided iterator (leader): ",
                       here.locale, ", tid ", 0, ": yielding range ",
                       unDensify(current,c),
                       " (", current.length, "/", iterCount, ")",
                       " as ", current);

          yield (current,);

          cachedIndex=meitneriumIndex.fetchAdd(1);
        }

        /*

        var getMoreWork=true;
        var localIterCount:int;
        var localWork:cType;

        while getMoreWork do
        {
          if moreWork
          then
          {
            localWork=adaptSplit(remain,
                                 factor,
                                 moreWork,
                                 profThreshold=chunkThreshold);
            localIterCount=localWork.length;
            if localIterCount == 0 then getMoreWork=false;
          }
          else getMoreWork=false;

          if getMoreWork then
          {
            const nTasks=min(localIterCount, defaultNumTasks(numTasks));
            const localFactor=nTasks;

            // TODO: Why if we define these just after "if L != masterLocale
            // ..." do we get an erroneous iteration?
            var localLock:vlock;
            var moreLocalWork=true;

            // TODO: Can we simply employ the single-locale guided iterator
            // here? (Tried once and failed correctness test.)
            coforall tid in 0..#nTasks
            with (ref localLock, ref localWork, ref moreLocalWork) do
            {
              while moreLocalWork do
              {
                const current:cType=adaptSplit(localWork,
                                               localFactor,
                                               moreLocalWork,
                                               localLock);
                if current.length != 0 then
                {
                  if debugDistributedIters
                  then writeln("Distributed guided iterator (leader): ",
                               here.locale, ", tid ", tid, ": yielding range ",
                               unDensify(current,localWork),
                               " (", current.length, "/", localIterCount, ")",
                               " as ", current);

                  yield (current,);
                }
              }
            }
          }
        }
        */
      }
    }
  }
}
pragma "no doc"
iter guidedDistributed(param tag:iterKind,
                       c:range(?),
                       numTasks:int,
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

private proc adaptSplit(ref rangeToSplit:range(?),
                        splitFactor:int,
                        ref itLeft:bool,
                        ref lock:vlock,
                        splitTail:bool=false,
                        profThreshold:int=1)
{
  type rType=rangeToSplit.type;
  type lenType=rangeToSplit.length.type;

  var initialSubrange:rType;
  var totLen, size : lenType;

  lock.lock();
  totLen=rangeToSplit.length;
  if totLen > profThreshold
  then size=max(totLen/splitFactor, profThreshold);
  else
  {
    size = totLen;
    itLeft = false;
  }
  if size == totLen
  then
  {
    itLeft = false;
    initialSubrange = rangeToSplit;
    rangeToSplit = 1..0;
  }
  else
  {
    const direction = if splitTail then -1 else 1;
    initialSubrange = rangeToSplit#(direction*size);
    rangeToSplit = rangeToSplit#(direction*(size-totLen));
  }
  lock.unlock();
  return initialSubrange;
}

} // End of module.
