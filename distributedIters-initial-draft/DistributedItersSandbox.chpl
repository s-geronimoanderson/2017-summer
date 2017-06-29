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
                       minChunkSize:int=0,
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
                       minChunkSize:int=0,
                       coordinated:bool=false)
where tag == iterKind.leader
{
  assert(minChunkSize >= 0, "minChunkSize must be a positive integer");

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
    const chunkThreshold:int=if minChunkSize == 0
                             then divceilpos(iterCount, numLocales):int
                             else minChunkSize;

    /*
    const factor=numLocales;
    const masterLocale=here.locale;
    var lock:vlock;
    var moreWork=true;
    */

    coforall L in Locales
    with (ref lock, ref moreWork, ref remain) do
    on L do
    {

      if (supervised && L != masterLocale) || numLocales == 1
      then
      {
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
                                 lock,
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
                       minChunkSize:int=0,
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

// An atomic test-and-set lock.
pragma "no doc"
record vlock
{
  var l: atomic bool;
  proc lock()
  {
    on this
    do while l.testAndSet() != false
       do chpl_task_yield();
  }
  proc unlock()
  {
    l.write(false);
  }
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
