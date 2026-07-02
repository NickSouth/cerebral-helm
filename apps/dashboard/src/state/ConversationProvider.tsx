import { createContext, useContext, useRef, useState, type ReactNode } from "react";
import type { ConversationMessage } from "../bridge/types";
import { useBridge } from "./BridgeProvider";
import { useDashboardState } from "./DashboardStateProvider";

interface ConversationContextValue {
  readonly open: boolean;
  readonly messages: readonly ConversationMessage[];
  /** Submit text from either input locus: opens the conversation and appends the exchange. */
  submit(text: string): void;
  /**
   * Append a single Heimlich-authored acknowledgement and open the conversation — the honest
   * channel for a wired action's result (e.g. a captured note's id). Not a user turn, so it
   * dispatches no command and fabricates no richer outcome than the bridge actually returned.
   */
  acknowledge(text: string): void;
  /** Minimize/close the conversation overlay; the ambient field returns to full idle. */
  close(): void;
}

const ConversationContext = createContext<ConversationContextValue | null>(null);

const MOCK_REPLY =
  "Heimlich is a mock pre-Mac — live reasoning arrives with the model integration.";

/**
 * The Heimlich conversation as interactive session state. Seeded from
 * `bootstrap.heimlich.conversation`; the C0 launcher and the docked input both submit here.
 * Submitting also dispatches `submitCommand` through the bridge (honest, acknowledged) — the
 * reply is a labelled mock, never a fake successful result. NIC-60 renders the real field and
 * may migrate this to bridge-driven state.
 */
export function ConversationProvider({ children }: { children: ReactNode }) {
  const bridge = useBridge();
  const seed = useDashboardState().heimlich.conversation;
  const [open, setOpen] = useState(seed.open);
  const [messages, setMessages] = useState<readonly ConversationMessage[]>(() => [
    ...seed.transcript
  ]);
  const counter = useRef(0);

  function nextId(): string {
    counter.current += 1;
    return `msg-${counter.current}`;
  }

  function submit(text: string): void {
    const trimmed = text.trim();
    if (!trimmed) {
      return;
    }
    const userMessage: ConversationMessage = { id: nextId(), role: "user", text: trimmed };
    const reply: ConversationMessage = { id: nextId(), role: "heimlich", text: MOCK_REPLY };
    setMessages((previous) => [...previous, userMessage, reply]);
    setOpen(true);
    void bridge.submitCommand({ rawInput: trimmed, source: "command-surface" });
  }

  function acknowledge(text: string): void {
    const trimmed = text.trim();
    if (!trimmed) {
      return;
    }
    const message: ConversationMessage = { id: nextId(), role: "heimlich", text: trimmed };
    setMessages((previous) => [...previous, message]);
    setOpen(true);
  }

  function close(): void {
    setOpen(false);
  }

  return (
    <ConversationContext.Provider value={{ open, messages, submit, acknowledge, close }}>
      {children}
    </ConversationContext.Provider>
  );
}

export function useConversation(): ConversationContextValue {
  const value = useContext(ConversationContext);

  if (value === null) {
    throw new Error("useConversation must be used within a ConversationProvider.");
  }

  return value;
}
