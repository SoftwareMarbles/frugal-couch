[ ![Codeship Status for SoftwareMarbles/frugal-couch](https://www.codeship.io/projects/42664c00-dcbd-0131-867d-7e56761d162f/status)](https://www.codeship.io/projects/24565)

frugal-couch
============

A node module that allows minimization of the number of HTTP requests to CouchDb/Cloudant. `frugal-couch` is build on top of [`nano`](https://github.com/dscape/nano).

It offers three functions:

### `overwriteBulk`

`overwriteBulk` is a function designed to perform bulk updating of given documents even when their revision values are out of date.

Bulk updating documents have two significant advantages over updating them one by one:

1.It's much faster as it requires only two trips to CouchDb for all the docs vs. two trips for each doc (one trip to try to update and if that fails then a new trip with corrected revision value)
2.It's much cheaper if used on DaaS like Cloudant which charge the same for bulk requests and non-bulk requests (so if you have 10,000 docs that you need to update you'll be charged for 2 requests and not for 20,000 requests)

Bulk updating shouldn't be used always unless you are absolutely certain that nothing else is updating your database. It can be very useful even in multi-client databases as some types of documents may considered to be stable and depending only on external values (e.g. importing Facebook Graph data)

This function accepts three parameters:

1.`database`: [`nano`](https://github.com/dscape/nano) database object (or an object with equivalent semantics) used to access the database

2.`docs`: an array of documents that need to be bulk-updated

3.`callback`: function with `(err, result)` signature. `result` is an object containing `inserted`, `updated`, `resurected` arrays and `revs` and `errors` objects. The three arrays hold the ids of inserted, updated and resurected documents (previously deleted and now re-inserted) while the two objects have properties matching document ids and their latest revisions or CouchDb generated errors respectively. `callback` is always invoked asynchronously

#### Example

```js
docs = [
    { _id: '1' },
    { _id: '2' },
    { _id: '3' },
    { _id: '4' }
]

frugal.overwriteBulk(database, docs, function(err, result) {
    //  get the IDs of the inserted, updated and resurected docs from `result`'s arrays
    //  also get the doc revisions (e.g. `result.revs['1']`) and document
    //  related errors (e.g. `result.error['1']`)
});
```

### `partialUpdateBulk`

`partialUpdateBulk` function performs partial updates of the documents with the given IDs.

CouchDb allows partial server-side modification of documents through its update handler feature. However, this feature doesn't work for arrays of documents and is thus too slow for massive document updates.

The alternative is to retrieve all the documents, apply the modification function to them and then bulk upload them. This is what `partialUpdateBulk` does.

This function accepts the following parameters:

1.`database`    -   `nano` database object or an object with equivalent semantics

2.`docIds`      -   the array of IDs of the documents to update

3.`partialUpdater`  -   the function accepting a single parameter (`doc` representing a database document) that does the document update and which will be invoked for each retrieved document

4.`callback`    -   function accepting `err` and `result` parameters:

 - `err`      -   error value in case of any error, falsy otherwise
 - `result`   -   object with `revs` and `errors` object properties. `revs` maps the document IDs to their post-operation revision while errors maps any CouchDb errors to document ID related to it

#### Example

```js
frugal.partialUpdateBulk(database, ['1', '3'], function(doc) {
    //  update `doc`'s state
}, function(err, result) {
    //  get revisions from `result.revs` (e.g. `result.revs['1']`)
    //  get errors from `result.errors` (e.g. `result.errors['1']`)
});
```

### `iterateViewBulk`

`iterateViewBulk` function is used to iterate over CouchDb views.

This function accepts the following parameters:

1.`database`    -   `nano` database object or an object with equivalent semantics

2.`designDoc`   -   the name of the design document in which the view is to be found.

3.`viewName`    -   the name of the view which will be queried.

4.`options`     -   standard CouchDb options like `startkey` and `endkey`. It also holds the number of documents in each desired iteration in its `limit` property. If it doesn't then the default batch size is 1,000 documents (completely arbitrary number). One property that this function ignores is `skip` as it's needed to perform correct and optimal iterations.

5.`iterator`    -   function accepting `err`, `docs` and `next` parameters:

 - `err`      -   error value in case of any error, falsy otherwise
 - `rows`     -   the array of view entries in the current iteration
 - `next`     -   the function to be invoked when the next iteration should be performed

#### Example

```js
frugal.iterateViewBulk(database, 'some', 'view', { limit: 15, include_docs: true }, function(err, rows, next) {
    //  unless there is an error iterate over `rows` and then invoke `next`
    //  if `rows` is empty or `next` is not defined, stop invoking `next`
});
```

## License

The MIT License (MIT)

Copyright (c) 2014 Software Marbles SpA

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
