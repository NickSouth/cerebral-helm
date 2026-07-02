import { CommandSurface } from "./CommandSurface";
import { useConversation } from "../state/ConversationProvider";

/**
 * The Heimlich conversation overlay (design spec §5.7, course-correction A.3/C): a translucent
 * surface composited over the still-running ambient field (it never replaces the center), with
 * a scrim for contrast, a minimize control, and the docked bottom input that continues the
 * exchange. NIC-60 renders the generative field beneath and polishes the composite.
 */
export function ConversationOverlay() {
  const { messages, submit, close } = useConversation();

  return (
    <div className="conversation" role="dialog" aria-label="Heimlich conversation">
      <div className="conversation__header">
        <p className="eyebrow">Conversation</p>
        <button type="button" className="conversation__close" onClick={close}>
          Minimize
        </button>
      </div>

      <ul className="conversation__transcript">
        {messages.map((message) => (
          <li
            key={message.id}
            className={`conversation__message conversation__message--${message.role}`}
          >
            <span className="conversation__role">
              {message.role === "user" ? "You" : "Heimlich"}
            </span>
            <span className="conversation__text">{message.text}</span>
          </li>
        ))}
      </ul>

      <div className="conversation__input">
        <CommandSurface
          variant="docked"
          placeholder="Continue the conversation…"
          ariaLabel="Continue the conversation"
          onSubmit={submit}
        />
      </div>
    </div>
  );
}
