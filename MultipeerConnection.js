var React = require('react-native');
var {
  DeviceEventEmitter,
  NativeModules
} = React;
var EventEmitter = require('events').EventEmitter;
var RCTMultipeerConnectivity = NativeModules.MultipeerConnectivity;
var Peer = require('./Peer');

class MultipeerConnection extends EventEmitter {

  constructor() {
    super();
    this._peers = {};
    this._connectedPeers = {};
    var peerFound = DeviceEventEmitter.addListener(
      'RCTMultipeerConnectivityPeerFound',
      ((event) => {
        console.log('RCTMultipeerConnectivityPeerFound', event);
        var peer = new Peer(event.peer.id, event.peer.info);
        this._peers[peer.id] = peer;
        this.emit('peerFound', {
          peer,
          self: event.self
        });
      }).bind(this));

    var peerLost = DeviceEventEmitter.addListener(
      'RCTMultipeerConnectivityPeerLost',
      ((event) => {
        console.log('RCTMultipeerConnectivityPeerLost', event);
        var peer = this._peers[event.peer.id];
        peer && peer.emit('lost');
        peer && this.emit('peerLost', {
          peer: {
            id: peer.id
          }
        });
        delete this._peers[event.peer.id];
        delete this._connectedPeers[event.peer.id];
      }).bind(this));

    var peerConnected = DeviceEventEmitter.addListener(
      'RCTMultipeerConnectivityPeerConnected',
      ((event) => {
        console.log('RCTMultipeerConnectivityPeerConnected', event);
        if (this._peers[event.peer.id]) {
          this._peers[event.peer.id].emit('connected');
          this._connectedPeers[event.peer.id] = this._peers[event.peer.id];
        } else {
          console.log('RCTMultipeerConnectivityPeerConnected', 'missing peer');
        }
        this.emit('peerConnected', event);
      }).bind(this));

    var peerConnecting = DeviceEventEmitter.addListener(
      'RCTMultipeerConnectivityPeerConnecting',
      ((event) => {
        console.log('RCTMultipeerConnectivityPeerConnecting', event);
        if (this._peers[event.peer.id]) {
          this._peers[event.peer.id].emit('connecting');
        } else {
          console.log('RCTMultipeerConnectivityPeerConnecting', 'missing peer');
        }
        this.emit('peerConnecting', event);
      }).bind(this));

    var peerDisconnected = DeviceEventEmitter.addListener(
      'RCTMultipeerConnectivityPeerDisconnected',
      ((event) => {
        console.log('RCTMultipeerConnectivityPeerDisconnected', event);
        if (this._peers[event.peer.id]) {
          this._peers[event.peer.id].emit('disconnected');
          delete this._connectedPeers[event.peer.id];
        } else {
          console.log('RCTMultipeerConnectivityPeerDisconnected', 'missing peer');
        }
        this.emit('peerDisconnected', event);
      }).bind(this));

    var streamOpened = DeviceEventEmitter.addListener(
      'RCTMultipeerConnectivityStreamOpened',
      ((event) => {
        console.log('RCTMultipeerConnectivityStreamOpened', event);
        this.emit('streamOpened', event);
      }).bind(this));

    var invited = DeviceEventEmitter.addListener(
      'RCTMultipeerConnectivityInviteReceived',
      ((event) => {
        console.log('RCTMultipeerConnectivityInviteReceived', event);
        event.sender = this._peers[event.peer.id];
        this.emit('invite', event);
      }).bind(this));

    var dataReceived = DeviceEventEmitter.addListener(
      'RCTMultipeerConnectivityDataReceived',
      ((event) => {
        console.log('RCTMultipeerConnectivityDataReceived', event);
        event.sender = this._peers[event.peer.id];
        this.emit('data', event);
      }).bind(this));
  }

  getAllPeers(callback) {
    RCTMultipeerConnectivity.getAllPeers(callback);
  }

  getConnectedPeers(callback) {
    RCTMultipeerConnectivity.getConnectedPeers(callback);
  }

  send(recipients, data, callback, forwardEnabled = false) {
    console.log('RCTMultipeer', 'send');
    if (!callback) {
      callback = () => { };
    }

    var recipientIds = recipients.map((recipient) => {
      if (recipient instanceof Peer) {
        return recipient.id;
      }
      return recipient;
    });

    RCTMultipeerConnectivity.send(recipientIds, data, forwardEnabled, callback);
  }

  broadcast(data, callback, forwardEnabled = false) {
    console.log('RCTMultipeer', 'broadcast');
    if (!callback) {
      callback = () => { };
    }
    RCTMultipeerConnectivity.broadcast(data, forwardEnabled, callback);
  }

  invite(peerId, callback) {
    console.log('RCTMultipeer', 'invite', peerId);
    if (!callback) {
      callback = () => { };
    }
    RCTMultipeerConnectivity.invite(peerId, callback);
  }

  rsvp(inviteId, accept, callback) {
    console.log('RCTMultipeer', 'rsvp', inviteId, accept);
    if (!callback) {
      callback = () => { };
    }
    RCTMultipeerConnectivity.rsvp(inviteId, accept, callback);
  }

  advertise(channel, info) {
    console.log('RCTMultipeer', 'advertise', channel, info);
    RCTMultipeerConnectivity.advertise(channel, info);
  }

  browse(channel) {
    console.log('RCTMultipeer', 'browse', channel);
    this._peers = {};
    RCTMultipeerConnectivity.browse(channel);
  }

  endAdvertise() {
    console.log('RCTMultipeer', 'endAdvertise');
    RCTMultipeerConnectivity.endAdvertise();
  }

  endBrowse() {
    console.log('RCTMultipeer', 'endBrowse');
    RCTMultipeerConnectivity.endBrowse();
  }

  disconnect() {
    console.log('RCTMultipeer', 'disconnect');
    RCTMultipeerConnectivity.disconnect(() => {
      this._peers = {};
    });
  }

  //  createStreamForPeer(peerId, name, callback) {
  //    if (!callback) {
  //      callback = () => {};
  //    }
  //    RCTMultipeerConnectivity.createStreamForPeer(peerId, name, callback);
  //  }
}

module.exports = MultipeerConnection;
