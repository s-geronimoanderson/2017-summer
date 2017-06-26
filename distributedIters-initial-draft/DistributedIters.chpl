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
module DistributedIters
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

// Experiment.
private proc defaultNumTasks(nTasks:int)
{
  var dnTasks=nTasks;
  if nTasks==0 then
  {
    if dataParTasksPerLocale==0
    then dnTasks=here.maxTaskPar;
    else dnTasks=dataParTasksPerLocale;
  }
  else if nTasks<0 then halt("'numTasks' is negative");
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
  proc unlock() {
    l.write(false);
  }
}

/*
private proc serveWork(ref rangeToSplit:range(?),
                       splitFactor:int,
                       ref lock:vlock,
                       splitTail:bool=false)
{
  return rangeToSplit;
}
*/

private proc adaptSplit(ref rangeToSplit:range(?),
                        splitFactor:int,
                        ref itLeft:bool,
                        ref lock:vlock,
                        splitTail:bool=false)
{
  type rType=rangeToSplit.type;
  type lenType=rangeToSplit.length.type;

  const profThreshold=1;

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




iter guidedDistributed(c:range(?),
                       numTasks:int=0)
{
  if debugDistributedIters
  then writeln("Serial guided iterator, working with range ", c);

  for i in c do yield i;
}

/* Standalone?
iter guided(param tag:iterKind,
            c:range(?),
            numTasks:int=0)
where tag == iterKind.standalone
{
  if debugDistributedIters
  then writeln("Standalone guided iterator, working with range ", c);

  for i in c do yield i;
}
*/

pragma "no doc"
iter guidedDistributed(param tag:iterKind,
                       c:range(?),
                       numTasks:int=0)
where tag == iterKind.leader
{
  const iterCount=c.length;
  if iterCount == 0 then halt("The range is empty");

  type cType=c.type;
  var remain:cType = densify(c,c);

  if iterCount == 1 || numTasks == 1 && numLocales == 1 then
  {
    if debugDistributedIters
    then writeln("Distributed guided iterator: serial execution due to ",
                 "insufficient work or compute resources");
    yield (remain,);
  }
  else
  {
    const factor=numLocales;
    const masterLocale=here.locale;
    var lock:vlock;
    var moreWork=true;

    // coforall loc in Locales do on loc {
    coforall L in Locales
    with (ref lock, ref moreWork, ref remain) do
    on L do
    {
      if L != masterLocale || numLocales == 1
      then
      {
        var moreLocalWork=true;
        var localWork:cType;

        while moreLocalWork do
        {
          if moreWork
          then
          {
            localWork=adaptSplit(remain, factor, moreWork, lock);
            if localWork.length == 0 then moreLocalWork=false;
          }
          else moreLocalWork=false;

          if moreLocalWork then
          {
            // Divide work per processor using single-locale guided iterator.
            const localIterCount=localWork.length;
            if localIterCount == 0 then halt("The range is empty");
            const nTasks=min(localIterCount, defaultNumTasks(numTasks));
            const localFactor=nTasks;
            var localLock:vlock;

            /* Don't need to do it ourselves?
            coforall tid in 0..#nTasks
            with (ref localWork, ref moreLocalWork, ref localLock) do
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
                               unDensify(current,c),
                               " (", current.length, "/", localIterCount, ")",
                               " as ", current);
                  yield (current,);
                }
              }
            }
            */

            // Single-threaded locale-specific version.
            if debugDistributedIters
            then writeln("Distributed guided iterator (leader): ",
                         here.locale, ": yielding range ",
                         unDensify(localWork,c),
                         " (", localIterCount, "/", iterCount, ")",
                         " as ", localWork);

            for i in guided(tag=iterKind.leader, localWork, nTasks) do
              yield i;
          }
        }
      }
    }

    /*
    coforall L in Locales
    with (ref remain, ref moreWork, ref lock) do
    {
      on L do
      {
        // Divide work per processor.
        //const nTasks=min(iterCount, defaultNumTasks(numTasks));
        const nTasks = 1;
        coforall tid in 0..#nTasks
        with (ref remain, ref moreWork, ref lock) do
        {
          lock.lock();
          while moreWork do
          {
            lock.unlock();
            const current:cType=adaptSplit(remain, factor, moreWork, lock);
            if current.length != 0 then
            {
              if debugDistributedIters
              then writeln("Distributed guided iterator (leader): Locale ",
                           here.id, ", tid ", tid, ", yielding range ",
                           unDensify(current,c),
                           " (", current.length, "/", iterCount, ")",
                           " as ", current);
              yield (current,);
            }
          }
        }
      }
    }
    */

    /*
    // Divide work per processor.
    coforall tid in 0..#nTasks
    with (ref remain, ref moreLocalWork, ref lock) do
    {
      while moreLocalWork do
      {
        const current:cType=adaptSplit(remain, factor, moreLocalWork, lock);
        if current.length != 0 then
        {
          if debugDistributedIters
          then writeln("Distributed guided iterator (leader): Locale ",
                       here.id, ", tid ", tid, ", yielding range ",
                       unDensify(current,c),
                       " (", current.length, "/", iterCount, ")",
                       " as ", current);
          yield (current,);
        }
      }
    }
    */
  }
}

// Follower
pragma "no doc"
iter guidedDistributed(param tag:iterKind,
                       c:range(?),
                       numTasks:int,
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

} // End of module.
