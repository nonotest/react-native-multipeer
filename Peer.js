var EventEmitter = require('events').EventEmitter;

class Peer extends EventEmitter {
  constructor(id, info) {
    super();
    this.id = id;
    this.info = info;
  }
}

module.exports = Peer;
