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


writeln("This program is running on ", numLocales, " locales");


// Toggle debugging output.
config param debugDistributedIters:bool=true;

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
    write(i, " ");
    yield i;
  }
  writeln();

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
// An atomic test-and-set lock.
pragma "no doc"
record vlock
{
  var l: atomic bool;
  proc lock()
  {
    on this do while l.testAndSet() != false do chpl_task_yield();
  }
  proc unlock()
  {
    l.write(false);
  }
}

iter guided(c:range(?),
            numTasks:int=0)
{
  if debugDistributedIters
  then writeln("Serial guided iterator, working with range ", c);

  for i in c do yield i;
}

pragma "no doc"
iter guided(param tag:iterKind,
            c:range(?),
            numTasks:int=0)
where tag == iterKind.leader
{
  // Check if the number of tasks is 0, in that case it returns a default value
  const nTasks=min(c.length, defaultNumTasks(numTasks));

  type cType=c.type;
  var remain:cType = densify(c,c);

  // If the number of tasks is insufficient, yield in serial
  if c.length == 0 then halt("The range is empty");

  if nTasks == 1 then
  {
    if debugDistributedIters
    then writeln("Guided iterator: serial execution because there is not ",
                 "enough work");
    yield (remain,);
  }
  else
  {
    var undone=true;
    const factor=nTasks;
    var lock : vlock;

    coforall tid in 0..#nTasks with (ref remain, ref undone, ref lock) do
    {
      while undone do
      {
        // There is local work in remain(tid)
        const current:cType=adaptSplit(remain, factor, undone, lock);
        if current.length !=0 then
        {
          if debugDistributedIters
          then writeln("Parallel guided Iterator. Working at tid ", tid,
                       " with range ", unDensify(current,c),
                       " yielded as ", current);
          yield (current,);
        }
      }
    }
  }
}

// Follower
pragma "no doc"
iter guided(param tag:iterKind,
            c:range(?),
            numTasks:int,
            followThis)
where tag == iterKind.follower
{
  type cType=c.type;
  const current:cType=unDensify(followThis(1),c);
  if debugDistributedIters
  then writeln("Follower received range ", followThis,
               " ; shifting to ", current);
  for i in current do yield i;
}

} // End of module.
