(function() {
  var debug, _;

  _ = require('lodash');

  debug = (require('debug'))('frugal-couch');

  exports.overwriteBulk = function(database, docs, callback) {
    var getResultObject, idDocsMap;
    getResultObject = function(inserted, updated, resurected, revs, errors) {
      return {
        inserted: inserted || [],
        updated: updated || [],
        resurected: resurected || [],
        revs: revs || {},
        errors: errors || {}
      };
    };
    if (!_.isFunction(callback)) {
      throw new Error('Callback parameter required');
    }
    if (!database || !_.isArray(docs)) {
      debug('Bad input parameters passed to overwriteBulk function');
      return process.nextTick(function() {
        return callback(new Error('Bad input parameters'));
      });
    }
    if (_.isEmpty(docs)) {
      return process.nextTick(function() {
        return callback(null, getResultObject());
      });
    }
    debug('Overwritting', docs.length, 'docs in bulk');
    idDocsMap = {};
    _.each(docs, function(doc) {
      return idDocsMap[doc._id] = doc;
    });
    debug('Fetching doc revisions');
    return database.fetch_revs({
      keys: Object.keys(idDocsMap)
    }, function(err, revisions) {
      var inserted, resurected, updated;
      if (err) {
        return callback(err);
      }
      if (!revisions) {
        return callback(new Error('Invalid document revisions returned.'));
      }
      debug('Updating docs with correct revisions');
      inserted = [];
      updated = [];
      resurected = [];
      _.each(revisions.rows, function(row) {
        var doc, docId, _ref;
        if (!row) {
          return debug('Bad revision item received');
        }
        docId = row.key;
        if (!docId) {
          return debug('Bad document id received', docId);
        }
        if (row.error) {
          if (row.error === 'not_found') {
            delete idDocsMap[docId]._rev;
            inserted.push(docId);
          } else {
            debug('Error received', row.error);
          }
          return;
        }
        if (!((_ref = row.value) != null ? _ref.rev : void 0)) {
          return debug('Bad revision value received');
        }
        doc = idDocsMap[docId];
        if (!doc) {
          return debug('Bad document id', docId);
        }
        if (row.value.deleted) {
          delete doc._rev;
          return resurected.push(docId);
        } else {
          doc._rev = row.value.rev;
          return updated.push(docId);
        }
      });
      debug('Inserting', inserted.length, 'docs');
      debug('Updating', updated.length, 'docs');
      debug('Resurecting', resurected.length, 'docs');
      return database.bulk({
        docs: docs
      }, function(err, body) {
        var errors, revs;
        revs = {};
        errors = {};
        _.each(body, function(row) {
          if (row.ok) {
            return revs[row.id] = row.rev;
          } else {
            return errors[row.id] = {
              id: row.id,
              error: row.error,
              reason: row.reason
            };
          }
        });
        return callback(err, getResultObject(inserted, updated, resurected, revs, errors));
      });
    });
  };

  exports.partialUpdateBulk = function(database, docIds, partialUpdater, callback) {
    var getResultObject;
    getResultObject = function(revs, errors) {
      return {
        revs: revs || {},
        errors: errors || {}
      };
    };
    if (!_.isFunction(callback)) {
      throw new Error('Callback parameter required');
    }
    if (!database || !_.isArray(docIds) || !_.isFunction(partialUpdater)) {
      debug('Bad input parameters passed to partialUpdateBulk function');
      return process.nextTick(function() {
        return callback(new Error('Bad input parameters'));
      });
    }
    if (_.isEmpty(docIds)) {
      return process.nextTick(function() {
        return callback(null, getResultObject());
      });
    }
    debug('Partial bulk updating', docIds.length, 'docs');
    return database.fetch({
      keys: docIds
    }, function(err, body) {
      var docs;
      if (err) {
        return callback(err);
      }
      if (_.isEmpty(body != null ? body.rows : void 0)) {
        return callback(new Error('Invalid documents returned.'));
      }
      docs = [];
      _.each(body.rows, function(row) {
        var doc;
        doc = row.doc;
        docs.push(doc);
        return partialUpdater(doc);
      });
      return database.bulk({
        docs: docs
      }, function(err, body) {
        var errors, revs;
        revs = {};
        errors = {};
        _.each(body, function(row) {
          if (row.ok) {
            return revs[row.id] = row.rev;
          } else {
            return errors[row.id] = {
              id: row.id,
              error: row.error,
              reason: row.reason
            };
          }
        });
        return callback(err, getResultObject(revs, errors));
      });
    });
  };

  exports.iterateViewBulk = function(database, designDoc, viewName, options, iterator) {
    var nextIteration;
    if (!iterator) {
      iterator = options;
      options = void 0;
    }
    options = _.clone(options) || {};
    options.skip = 0;
    options.limit = options.limit || 1000;
    if (!_.isFunction(iterator)) {
      throw new Error('Iterator parameter required');
    }
    if (!database || !designDoc || !viewName || !options) {
      debug('Bad input parameters passed to iterateViewBulk function');
      return process.nextTick(function() {
        return iterator(new Error('Bad input parameters'));
      });
    }
    nextIteration = function() {
      return database.view(designDoc, viewName, options, function(err, body) {
        if (err) {
          return iterator(err);
        }
        if (!body || _.isEmpty(body.rows)) {
          return iterator(null, []);
        }
        options.skip = options.skip + body.rows.length;
        return iterator(null, body.rows, nextIteration);
      });
    };
    return nextIteration();
  };

}).call(this);
