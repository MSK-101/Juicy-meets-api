'use client';

import React, { useRef, useEffect, useState } from 'react';
import LogoPill from './LogoPill';
import DiamondPill from './DiamondPill';
import FlagPill from './FlagPill';
import SwipeButton from './SwipeButton';
import ChatOverlay from './ChatOverlay';
// @ts-expect-error PubNub has no type declarations for ESM import in Next.js
import PubNub, { ListenerParameters } from 'pubnub';

// DiamondIcon for coins display (used)
const DiamondIcon = () => (
  <svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
    <g filter="url(#filter0_d_1_2)">
      <path d="M14 4L24 14L14 24L4 14L14 4Z" fill="#7C3AED" stroke="#A78BFA" strokeWidth="2"/>
      <path d="M14 4L19 14L14 24L9 14L14 4Z" fill="#C4B5FD"/>
    </g>
    <defs>
      <filter id="filter0_d_1_2" x="0" y="0" width="28" height="28" filterUnits="userSpaceOnUse" colorInterpolationFilters="sRGB">
        <feFlood floodOpacity="0" result="BackgroundImageFix"/>
        <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape"/>
        <feGaussianBlur stdDeviation="2" result="effect1_foregroundBlur_1_2"/>
      </filter>
    </defs>
  </svg>
);

// --- Coin deduction rules (hardcoded, but structured for future backend) ---
const COIN_DEDUCTION_RULES = [
  // { seconds: after how many seconds, coins: how many coins to deduct }
  { seconds: 5, coins: 100 }, // every 5 seconds, deduct 100 coins
];

const INITIAL_COINS = 1000; // hardcoded, but from backend in future

// ENV VARS REQUIRED:
// NEXT_PUBLIC_PUBNUB_PUBLISH_KEY
// NEXT_PUBLIC_PUBNUB_SUBSCRIBE_KEY
// NEXT_PUBLIC_TURN_URL (TURN server URL, e.g. turn:global.relay.metered.ca:80)
// NEXT_PUBLIC_TURN_USERNAME (TURN username)
// NEXT_PUBLIC_TURN_CREDENTIAL (TURN credential/password)
// NEXT_PUBLIC_STUN_URL (optional, e.g. stun:stun.l.google.com:19302)

// ICE server config: use only envs for TURN/STUN (for production and local)
const getIceServers = () => {
  const stunUrl = process.env.NEXT_PUBLIC_STUN_URL;
  const turnUrl = process.env.NEXT_PUBLIC_TURN_URL;
  const turnUsername = process.env.NEXT_PUBLIC_TURN_USERNAME;
  const turnCredential = process.env.NEXT_PUBLIC_TURN_CREDENTIAL;
  const iceServers = [];
  if (stunUrl) {
    iceServers.push({ urls: stunUrl });
  }
  if (turnUrl && turnUsername && turnCredential) {
    iceServers.push({ urls: turnUrl, username: turnUsername, credential: turnCredential });
  }
  // Fallback to Google STUN if nothing set
  if (iceServers.length === 0) {
    iceServers.push({ urls: 'stun:stun.l.google.com:19302' });
  }
  return iceServers;
};

export default function RealVideoChat() {
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);
  const [chatMessages, setChatMessages] = useState<{ user: 'You' | 'Stranger'; message: string }[]>([]);
  const [inputValue, setInputValue] = useState('');
  const [dataChannelOpen, setDataChannelOpen] = useState(false);
  const [isInitialized, setIsInitialized] = useState(false);
  const [coins, setCoins] = useState(INITIAL_COINS);
  const [showCoinPopup, setShowCoinPopup] = useState(false);
  const [deductionTimer, setDeductionTimer] = useState<NodeJS.Timeout | null>(null);
  // Removed unused swipeCount
  const [isTyping, setIsTyping] = useState(false);
  const typingTimeout = useRef<NodeJS.Timeout | null>(null);

  const localVideoRef = useRef<HTMLVideoElement>(null);
  const remoteVideoRef = useRef<HTMLVideoElement>(null);
  // Types for ActionCable and ConnectionManager
  type ConnectionManagerRef = unknown;
  const connectionManagerRef = useRef<ConnectionManagerRef | null>(null);
  const pubnubRef = useRef<PubNub | null>(null);
  const pubnubListenerRef = useRef<Record<string, unknown> | null>(null);

  useEffect(() => {
    let SimplePeer: unknown;

    class ConnectionManager {
      public peer: unknown = null;
      private stream: MediaStream | null = null;
      private isInitiator: boolean = false;
      private hasReceivedOffer: boolean = false;
      private hasReceivedAnswer: boolean = false;
      private pendingSignals: unknown[] = [];
      private isDestroyed: boolean = false;

      constructor(stream: MediaStream, isInitiator: boolean) {
        this.stream = stream;
        this.isInitiator = isInitiator;
        this.createPeer();
      }

      private createPeer() {
        if (this.isDestroyed) return;
        this.peer = new (SimplePeer as unknown)({
          initiator: this.isInitiator,
          trickle: true,
          stream: this.stream,
          config: {
            iceServers: getIceServers()
          }
        });
        this.setupPeerEvents();
      }

      private setupPeerEvents() {
        (this.peer as unknown as { on: (event: string, cb: (data: unknown) => void) => void }).on('signal', (data: unknown) => {
          // Send signaling data via PubNub
          if (pubnubRef.current) {
            const ROOM = window.location.hash.replace('#', '') || 'default';
            const userId = sessionStorage.getItem('videochat_user_id') || 'unknown';
            pubnubRef.current.publish({
              channel: ROOM,
              message: { signal: data, sender: userId, room: ROOM } as Record<string, unknown>,
            });
          }
        });
        (this.peer as unknown as { on: (event: string, cb: (data: MediaStream) => void) => void }).on('stream', (remoteStream: MediaStream) => {
          if (remoteStream instanceof MediaStream) {
            console.log('[VideoChat] Received remote stream:', remoteStream);
            setRemoteStream(remoteStream);
            if (remoteVideoRef.current) {
              remoteVideoRef.current.srcObject = remoteStream;
              console.log('[VideoChat] Attached remote stream to video element.');
            }
          }
        });
        (this.peer as unknown as { on: (event: string, cb: () => void) => void }).on('connect', () => {
          setDataChannelOpen(true);
        });
        (this.peer as unknown as { on: (event: string, cb: (data: Uint8Array) => void) => void }).on('data', (data: Uint8Array) => {
          const msg = new TextDecoder().decode(data);
          setChatMessages(prev => [...prev, { user: 'Stranger', message: msg }]);
        });
        (this.peer as unknown as { on: (event: string, cb: () => void) => void }).on('close', () => {
          setRemoteStream(null);
          setDataChannelOpen(false);
        });
        (this.peer as unknown as { on: (event: string, cb: () => void) => void }).on('error', () => {
          setDataChannelOpen(false);
        });
      }

      public handleSignal(signal: unknown) {
        if (this.isDestroyed) return;
        if ((signal as unknown as { type?: string }).type === 'offer' && this.hasReceivedOffer) return;
        if ((signal as unknown as { type?: string }).type === 'answer' && this.hasReceivedAnswer) return;
        if ((signal as unknown as { type?: string }).type === 'offer') this.hasReceivedOffer = true;
        if ((signal as unknown as { type?: string }).type === 'answer') this.hasReceivedAnswer = true;
        if (!this.peer) {
          this.pendingSignals.push(signal);
          return;
        }
        try {
          (this.peer as unknown as { signal: (sig: unknown) => void }).signal(signal);
        } catch {}
      }

      public processPendingSignals() {
        if (this.isDestroyed) return;
        const signalsToProcess = [...this.pendingSignals];
        this.pendingSignals = [];
        signalsToProcess.forEach(signal => {
          setTimeout(() => {
            if (!this.isDestroyed) {
              this.handleSignal(signal);
            }
          }, 50);
        });
      }

      public destroy() {
        this.isDestroyed = true;
        if (this.peer) {
          (this.peer as unknown as { destroy: () => void }).destroy();
          this.peer = null;
        }
        this.pendingSignals = [];
      }
    }

    const initializeVideoChat = async () => {
      try {
        const [simplePeerModule] = await Promise.all([
          import('simple-peer')
        ]);
        SimplePeer = simplePeerModule.default;
        const ROOM = window.location.hash.replace('#', '') || Math.random().toString(36).substring(2, 10);
        const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
        if (localVideoRef.current) {
          localVideoRef.current.srcObject = stream;
        }
        // PubNub setup
        let userId = sessionStorage.getItem('videochat_user_id');
        if (!userId) {
          userId = crypto.randomUUID();
          sessionStorage.setItem('videochat_user_id', userId);
        }
        const joinedAtKey = `videochat_${ROOM}_joined_at`;
        let isInitiator = false;
        let joinedAt = localStorage.getItem(joinedAtKey);
        if (!joinedAt) {
          joinedAt = Date.now().toString();
          localStorage.setItem(joinedAtKey, joinedAt);
          isInitiator = true;
        } else {
          isInitiator = false;
        }
        console.log(`[VideoChat] userId=${userId} ROOM=${ROOM} isInitiator=${isInitiator}`);
        // Create PubNub client
        pubnubRef.current = new PubNub({
          publishKey: process.env.NEXT_PUBLIC_PUBNUB_PUBLISH_KEY! || 'pub-c-796ad0ea-9bff-4bbf-be5e-b269b3fe0325',
          subscribeKey: process.env.NEXT_PUBLIC_PUBNUB_SUBSCRIBE_KEY! || 'sub-c-7da9e1d6-9659-4ec5-ab27-d83f2b3d4e7c',
          uuid: userId,
        });
        // Listen for signaling messages
        pubnubListenerRef.current = {
          message: (event: ListenerParameters['message']) => {
            if (
              event &&
              typeof event === 'object' &&
              'message' in event &&
              event.message &&
              typeof event.message === 'object' &&
              'signal' in event.message &&
              'sender' in event.message &&
              'room' in event.message &&
              (event.message as { sender: string }).sender !== userId &&
              (event.message as { room: string }).room === ROOM
            ) {
              if (connectionManagerRef.current && typeof connectionManagerRef.current === 'object' && 'handleSignal' in connectionManagerRef.current) {
                (connectionManagerRef.current as { handleSignal: (signal: unknown) => void }).handleSignal((event.message as { signal: unknown }).signal);
              }
            }
          }
        };
        pubnubRef.current.addListener(pubnubListenerRef.current as ListenerParameters);
        pubnubRef.current.subscribe({ channels: [ROOM] });
        setTimeout(() => {
          connectionManagerRef.current = new ConnectionManager(stream, isInitiator) as unknown as ConnectionManagerRef;
          setTimeout(() => {
            if (
              connectionManagerRef.current &&
              typeof connectionManagerRef.current === 'object' &&
              'processPendingSignals' in connectionManagerRef.current &&
              typeof (connectionManagerRef.current as { processPendingSignals?: unknown }).processPendingSignals === 'function'
            ) {
              (connectionManagerRef.current as { processPendingSignals: () => void }).processPendingSignals();
            }
          }, 1000);
        }, 500);
        setIsInitialized(true);
      } catch (err) {
        console.error('[VideoChat] Initialization error', err);
      }
    };
    setTimeout(() => {
      initializeVideoChat();
    }, 200);
    return () => {
      if (
        connectionManagerRef.current &&
        typeof connectionManagerRef.current === 'object' &&
        'peer' in (connectionManagerRef.current as Record<string, unknown>)
      ) {
        const peer = (connectionManagerRef.current as Record<string, unknown>).peer;
        if (
          peer &&
          typeof peer === 'object' &&
          'destroy' in peer &&
          typeof (peer as { destroy?: unknown }).destroy === 'function'
        ) {
          (peer as { destroy: () => void }).destroy();
        }
        if (
          peer &&
          typeof peer === 'object' &&
          'removeAllListeners' in peer &&
          typeof (peer as { removeAllListeners?: unknown }).removeAllListeners === 'function'
        ) {
          (peer as { removeAllListeners: () => void }).removeAllListeners();
        }
      }
      if (pubnubRef.current && pubnubListenerRef.current) {
        pubnubRef.current.removeListener(pubnubListenerRef.current as ListenerParameters);
        pubnubRef.current.unsubscribeAll();
      }
    };
  }, []);

  useEffect(() => {
    if (remoteStream && remoteVideoRef.current) {
      remoteVideoRef.current.srcObject = remoteStream;
      remoteVideoRef.current.play().catch(() => {});
      const userId = sessionStorage.getItem('videochat_user_id');
      const ROOM = window.location.hash.replace('#', '') || 'unknown';
      console.log(`[VideoChat] useEffect: remoteStream attached for userId=${userId} ROOM=${ROOM}`, remoteStream);
    }
  }, [remoteStream]);

  // --- Coin deduction effect ---
  useEffect(() => {
    if (!remoteStream) {
      if (deductionTimer) {
        clearInterval(deductionTimer);
        setDeductionTimer(null);
      }
      return;
    }
    // Find the shortest deduction interval
    const minInterval = Math.min(...COIN_DEDUCTION_RULES.map(r => r.seconds));
    if (deductionTimer) clearInterval(deductionTimer);
    const timer = setInterval(() => {
      let coinsToDeduct = 0;
      COIN_DEDUCTION_RULES.forEach(rule => {
        if ((Date.now() / 1000) % rule.seconds < minInterval) {
          coinsToDeduct += rule.coins;
        }
      });
      setCoins(prev => {
        const next = prev - coinsToDeduct;
        if (next <= 0) {
          setShowCoinPopup(true);
          return 0;
        }
        return next;
      });
    }, minInterval * 1000);
    setDeductionTimer(timer);
    return () => clearInterval(timer);
  }, [remoteStream]);

  // --- When coins run out, stop video/chat ---
  useEffect(() => {
    if (coins <= 0) {
      // Optionally, stop video/chat here
      if (connectionManagerRef.current) {
        (connectionManagerRef.current as { destroy: () => void }).destroy();
      }
      setRemoteStream(null);
      setDataChannelOpen(false);
    }
  }, [coins]);

  // --- Swipe handler ---
  // handleSwipe removed if unused

  const handleSend = () => {
    if (!inputValue.trim() || !dataChannelOpen) return;

    // Check if connection manager and peer exist
    if (
      connectionManagerRef.current &&
      typeof connectionManagerRef.current === 'object' &&
      'peer' in (connectionManagerRef.current as Record<string, unknown>) &&
      (connectionManagerRef.current as Record<string, unknown>).peer &&
      typeof (connectionManagerRef.current as Record<string, unknown>).peer === 'object' &&
      'send' in (connectionManagerRef.current as Record<string, unknown>).peer &&
      typeof ((connectionManagerRef.current as Record<string, unknown>).peer as { send?: unknown }).send === 'function'
    ) {
      const peer = (connectionManagerRef.current as Record<string, unknown>).peer;
      (peer as { send: (msg: string) => void }).send(inputValue);
      setChatMessages(prev => [...prev, { user: 'You', message: inputValue }]);
      setInputValue('');
    }
  };

  // Typing indicator logic
  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setInputValue(e.target.value);
    setIsTyping(true);
    if (typingTimeout.current) clearTimeout(typingTimeout.current);
    typingTimeout.current = setTimeout(() => setIsTyping(false), 1200);
  };
  const handleInputFocus = () => {
    setIsTyping(true);
    if (typingTimeout.current) clearTimeout(typingTimeout.current);
  };
  const handleInputBlur = () => {
    typingTimeout.current = setTimeout(() => setIsTyping(false), 600);
  };

  return (
    <div className="h-[calc(100vh-80px)] w-full flex items-stretch overflow-hidden relative bg-[#181828]">
      {/* Left: Other User Panel */}
      <div className="flex-1 relative flex flex-col bg-[#181828] border-2 border-purple-400 rounded-2xl overflow-hidden">
        <LogoPill />
        <DiamondPill coins={coins} />
        {remoteStream ? (
          <video
            ref={remoteVideoRef}
            autoPlay
            playsInline
            className="w-full h-full object-cover rounded-none absolute inset-0 z-0"
            style={{ opacity: 0.9 }}
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-white text-lg font-normal">
            {isInitialized ? "Waiting for peer..." : "Initializing..."}
          </div>
        )}
        <SwipeButton />
      </div>
      {/* Right: Current User Panel */}
      <div className="flex-1 relative flex flex-col bg-[#181828] border-2 border-purple-400 rounded-2xl overflow-hidden">
        <FlagPill />
        <video
          ref={localVideoRef}
          autoPlay
          playsInline
          muted
          className="w-full h-full object-cover rounded-none"
        />
        {/* Typing indicator for current user */}
        {isTyping && (
          <div className="absolute bottom-28 left-1/2 -translate-x-1/2 z-30 px-5 py-1.5 rounded-full bg-white bg-opacity-60 text-gray-900 text-xs font-medium shadow-md backdrop-blur-md border border-purple-200">
            You are typing...
          </div>
        )}
        <ChatOverlay
          chatMessages={chatMessages}
          inputValue={inputValue}
          onInputChange={handleInputChange}
          onInputFocus={handleInputFocus}
          onInputBlur={handleInputBlur}
          onInputKeyDown={e => {
            if (e.key === 'Enter') {
              e.preventDefault();
              handleSend();
            }
          }}
          onSend={handleSend}
          dataChannelOpen={dataChannelOpen}
          coins={coins}
        />
        {/* Coins ended popup */}
        {showCoinPopup && (
          <div className="absolute inset-0 flex items-center justify-center z-50 bg-black bg-opacity-70">
            <div className="bg-white rounded-2xl px-8 py-6 shadow-xl flex flex-col items-center">
              <DiamondIcon />
              <div className="mt-4 text-base font-medium text-gray-900">Your coins have ended.</div>
              <button className="mt-6 px-6 py-2 bg-purple-600 text-white rounded-full font-semibold" onClick={() => setShowCoinPopup(false)}>Close</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
