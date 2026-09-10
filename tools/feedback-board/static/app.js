"use strict";

const $ = (selector, root = document) => root.querySelector(selector);
const state = { board: null, selection: null, token: null, pending: false, drag: null, connected: false, boardUnreadable: false };

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function showStatus(message, kind = "") {
  const node = $("#save-status");
  node.textContent = message;
  node.className = `save-status${kind ? ` is-${kind}` : ""}`;
}

function showError(message, dialog = null) {
  const banner = $("#error-banner");
  banner.textContent = message;
  banner.hidden = false;
  if (dialog) {
    const error = $(".dialog-error", dialog);
    error.textContent = message;
    error.hidden = false;
  }
  showStatus("Changes were not saved.", "error");
}

function clearError(dialog = null) {
  $("#error-banner").hidden = true;
  if (dialog) $(".dialog-error", dialog).hidden = true;
}

async function request(path, options = {}) {
  const response = await fetch(path, { cache: "no-store", ...options });
  let data;
  try { data = await response.json(); }
  catch (_) { throw new Error("The local server returned an unreadable response. Check that it is still running."); }
  if (!response.ok) {
    const error = new Error(data.error || `Request failed (${response.status}).`);
    error.status = response.status;
    throw error;
  }
  return data;
}

function setPending(pending) {
  state.pending = pending;
  for (const button of document.querySelectorAll(".mutation-action")) {
    const recoveryAction = ["restore-board", "recover-board"].includes(button.id) || Boolean(button.closest("#restore-dialog"));
    button.disabled = pending || button.dataset.unavailable === "true" || (!recoveryAction && (!state.board || state.boardUnreadable));
  }
  for (const button of document.querySelectorAll(".dialog-close")) button.disabled = pending;
}

function focusCard(key) {
  if (!key) return;
  const candidates = Array.from(document.querySelectorAll("[data-focus]"));
  let target = candidates.find(node => node.dataset.focus === key && !node.disabled);
  if (!target) {
    const itemId = key.split(":")[0];
    target = candidates.find(node => node.dataset.focus.startsWith(`${itemId}:`) && !node.disabled);
  }
  if (target) target.focus({ preventScroll: true });
}

async function refreshBoard({ announce = false } = {}) {
  let data;
  try { data = await request("/api/board"); }
  catch (error) {
    state.boardUnreadable = error.status >= 500;
    setPending(state.pending);
    throw error;
  }
  if (state.drag || (state.board && data.board.revision < state.board.revision)) return data;
  const changed = !state.board || data.board.revision !== state.board.revision;
  state.board = data.board;
  state.selection = data.selection;
  state.connected = true;
  state.boardUnreadable = false;
  if (changed) renderBoard();
  else setPending(state.pending);
  if (announce) showStatus(`Board loaded · revision ${state.board.revision}`);
  return data;
}

async function mutate(action, payload, { dialog = null, revision, focus, success } = {}) {
  if (state.pending) return false;
  clearError(dialog);
  setPending(true);
  showStatus("Saving…", "saving");
  try {
    if (!state.token) state.token = (await request("/api/session")).token;
    const data = await request("/api/action", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Feedback-Token": state.token },
      body: JSON.stringify({ revision: revision ?? state.board?.revision ?? -1, action, payload }),
    });
    state.board = data.board;
    state.selection = data.selection;
    state.connected = true;
    state.boardUnreadable = false;
    if (dialog) dialog.close();
    renderBoard();
    showStatus(success || `Saved · ${new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`);
    return true;
  } catch (error) {
    let message = error.message;
    if (error.status === 403) {
      state.token = null;
      message += " The server session may have changed. Your draft is kept; try saving again.";
    }
    if (error.status === 409) {
      try {
        await refreshBoard();
        if (dialog) dialog.dataset.revision = String(state.board.revision);
        message += " The latest board is now loaded. Your draft is kept; review it and try saving again.";
      } catch (_) { message += " Reload the board when the server is available. Your draft is kept."; }
    }
    showError(message, dialog);
    return false;
  } finally {
    setPending(false);
    if (!dialog || !dialog.open) focusCard(focus);
  }
}

function emptyState(title, description, symbol = null) {
  const node = element("div", "empty-state");
  if (symbol) {
    const mark = element("div", "empty-symbol", symbol);
    mark.setAttribute("aria-hidden", "true");
    node.append(mark);
  }
  node.append(element("p", "empty-title", title), element("p", "", description));
  return node;
}

function cardButton(item, text, action, options = {}) {
  const button = element("button", `${options.primary ? "button primary small-button" : "quiet-button"} mutation-action`, text);
  button.type = "button";
  button.dataset.focus = `${item.id}:${options.key || text}`;
  button.setAttribute("aria-label", `${text}: ${item.title}`);
  button.addEventListener("click", action);
  return button;
}

function changeStatus(item, status) {
  let success;
  if (status === "queued") {
    success = ["awaiting_playtest", "done", "archived"].includes(item.status)
      ? `Reopened “${item.title}” at the bottom of the queue.`
      : `Returned “${item.title}” to its existing queue position.`;
  }
  return mutate("status", { id: item.id, status, user_override: true }, { success });
}

function itemCard(item, queueIndex = null, queueItems = []) {
  const card = element("article", "feedback-card");
  card.dataset.itemId = item.id;
  if (queueIndex !== null) card.classList.add("queue-card");
  if (item.status === "blocked") card.classList.add("is-blocked");
  const next = state.selection?.kind === "next" && state.selection.item?.id === item.id;
  if (next) card.classList.add("is-next");

  if (queueIndex !== null) {
    const position = element("div", "queue-position");
    const number = element("span", "queue-number", String(queueIndex + 1).padStart(2, "0"));
    number.setAttribute("aria-label", `Queue position ${queueIndex + 1}`);
    position.append(number);
    const handle = element("span", "drag-handle", "⠿");
    handle.draggable = false;
    handle.title = "Drag to reorder. Use the arrow buttons for keyboard control.";
    handle.setAttribute("aria-hidden", "true");
    handle.addEventListener("pointerdown", event => startPointerDrag(event, item, card, queueItems));
    handle.addEventListener("pointermove", movePointerDrag);
    handle.addEventListener("pointerup", finishPointerDrag);
    handle.addEventListener("pointercancel", endDrag);
    handle.addEventListener("lostpointercapture", endDrag);
    handle.addEventListener("dragstart", event => event.preventDefault());
    position.append(handle);
    const moves = element("div", "move-buttons");
    for (const [direction, symbol, offset] of [["up", "↑", -1], ["down", "↓", 1]]) {
      const button = element("button", "move-button mutation-action", symbol);
      button.type = "button";
      button.dataset.focus = `${item.id}:move-${direction}`;
      button.setAttribute("aria-label", `Move ${item.title} ${direction}`);
      button.title = `Move ${direction}`;
      const unavailable = queueIndex + offset < 0 || queueIndex + offset >= queueItems.length;
      button.dataset.unavailable = String(unavailable);
      button.disabled = unavailable;
      button.addEventListener("click", () => {
        const ids = queueItems.map(entry => entry.id);
        [ids[queueIndex], ids[queueIndex + offset]] = [ids[queueIndex + offset], ids[queueIndex]];
        mutate("reorder", { ids }, { focus: button.dataset.focus, success: `Moved “${item.title}” to position ${queueIndex + offset + 1}.` });
      });
      moves.append(button);
    }
    position.append(moves);
    card.append(position);
  }

  const content = element("div", "card-content");
  const topline = element("div", "card-topline");
  topline.append(element("span", "item-id", item.id));
  if (next) topline.append(element("span", "badge badge-next", "Up next"));
  else if (item.status === "blocked") topline.append(element("span", "badge badge-blocked", "Blocked"));
  else if (item.status === "in_progress") topline.append(element("span", "badge badge-active", "Active"));
  content.append(topline, element("h3", "card-title", item.title));
  if (item.notes) content.append(element("p", "card-notes", item.notes));
  if (item.owner && item.status === "in_progress") content.append(element("p", "owner-label", `Task · ${item.owner}`));
  if (item.blocked_reason && item.status === "blocked") content.append(element("p", "blocked-reason", item.blocked_reason));

  const metadata = element("div", "metadata");
  if (item.build_id) metadata.append(element("span", "build-id", item.build_id));
  if (item.source_link) {
    try {
      const url = new URL(item.source_link);
      if (["http:", "https:"].includes(url.protocol)) {
        const link = element("a", "", "Source ↗");
        link.href = url.href;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.title = item.source_link;
        link.setAttribute("aria-label", `Open source for ${item.title} (new tab)`);
        metadata.append(link);
      }
    } catch (_) { /* Invalid imported links are never rendered as anchors. */ }
  }
  if (metadata.childNodes.length) content.append(metadata);

  const actions = element("div", "card-actions");
  if (item.status === "in_progress") {
    actions.append(cardButton(item, "Ready for playtest", () => changeStatus(item, "awaiting_playtest"), { primary: true }));
    actions.append(cardButton(item, "Release claim", () => mutate("status", { id: item.id, status: "queued", user_override: true }, { success: `Released “${item.title}” to its existing queue position.` })));
  }
  if (item.status === "awaiting_playtest") actions.append(cardButton(item, "Accept as done", () => changeStatus(item, "done"), { primary: true }));
  if (["awaiting_playtest", "done", "archived"].includes(item.status)) actions.append(cardButton(item, "Reopen", () => changeStatus(item, "queued")));
  actions.append(cardButton(item, "Edit", () => openFeedback(item)));
  if (["queued", "in_progress"].includes(item.status)) actions.append(cardButton(item, "Block", () => openBlock(item)));
  if (item.status === "blocked") actions.append(cardButton(item, "Unblock", () => mutate("status", { id: item.id, status: "queued", user_override: true }, { success: `Unblocked “${item.title}” in its existing position.` })));
  if (item.status !== "archived") actions.append(cardButton(item, "Archive", () => changeStatus(item, "archived")));
  content.append(actions);
  card.append(content);
  return card;
}

function renderBoard() {
  if (!state.board) return;
  const previousFocus = document.activeElement?.dataset.focus;
  const items = state.board.items;
  const queued = items.filter(item => ["queued", "blocked"].includes(item.status));
  $("#queue-count").textContent = String(queued.length);
  const queue = $("#queue");
  queue.replaceChildren();
  if (queued.length) queued.forEach((item, index) => queue.append(itemCard(item, index, queued)));
  else queue.append(emptyState("A clear queue. A fresh start.", "Add your first playtest observation or idea. Your next improvement starts here.", "◇"));

  for (const [status, id, title, description] of [
    ["in_progress", "active", "No work in progress", "Start the next item when you are ready to develop."],
    ["awaiting_playtest", "playtest", "Nothing waiting for playtest", "Implemented and verified fixes will appear here."],
    ["done", "done", "No completed feedback yet", "Accepted fixes stay here for reference."],
    ["archived", "archived", "No archived feedback", "Archived items can be reopened at any time."],
  ]) {
    const entries = items.filter(item => item.status === status);
    $("#" + id + "-count").textContent = String(entries.length);
    const container = $("#" + id + "-items");
    container.replaceChildren();
    if (entries.length) entries.forEach(item => container.append(itemCard(item)));
    else container.append(emptyState(title, description));
  }

  const selection = state.selection;
  const startButton = $("#start-work");
  startButton.hidden = selection?.kind !== "next";
  $("#next-label").textContent = selection?.kind === "active" ? "CURRENT PRIORITY" : "UP NEXT";
  if (selection?.kind === "active") {
    const activeCount = items.filter(item => item.status === "in_progress").length;
    $("#selection-title").textContent = selection.item.title;
    $("#selection-description").textContent = activeCount > 1
      ? `${activeCount} tasks in development · First active item belongs to ${selection.item.owner}`
      : `Continue the existing development claim · ${selection.item.owner}`;
  } else if (selection?.kind === "next") {
    $("#selection-title").textContent = selection.item.title;
    const blockedBefore = queued.slice(0, queued.findIndex(item => item.id === selection.item.id)).filter(item => item.status === "blocked").length;
    $("#selection-description").textContent = blockedBefore ? `First available item · ${blockedBefore} blocked ${blockedBefore === 1 ? "item keeps its" : "items keep their"} place above it.` : "First available item in your queue. Ready when you are.";
  } else if (selection?.kind === "blocked") {
    $("#selection-title").textContent = "All queued feedback is blocked";
    $("#selection-description").textContent = "Resolve a blocker or add new feedback to make the next item available.";
  } else {
    $("#selection-title").textContent = "You decide what comes next";
    $("#selection-description").textContent = "Add feedback to start your queue. Nothing starts automatically.";
  }
  setPending(state.pending);
  focusCard(previousFocus);
}

function openDialog(dialog) {
  dialog.dataset.revision = String(state.boardUnreadable ? -1 : state.board?.revision ?? -1);
  clearError(dialog);
  dialog.showModal();
}

function openFeedback(item = null) {
  const dialog = $("#feedback-dialog");
  $("#feedback-form").reset();
  dialog.dataset.itemId = item?.id || "";
  $("#feedback-dialog-title").textContent = item ? "Edit feedback" : "Add feedback";
  $("#feedback-dialog-description").textContent = item ? "Update the details. This does not change the item’s priority or status." : "Add an observation, a problem, or an idea. It joins the bottom of your queue.";
  $("#save-feedback").textContent = item ? "Save changes" : "Add to queue";
  for (const [name, id] of [["title", "title"], ["notes", "notes"], ["build_id", "build"], ["source_link", "source"]]) $("#feedback-" + id).value = item?.[name] || "";
  openDialog(dialog);
  $("#feedback-title").focus();
}

function openBlock(item) {
  const dialog = $("#block-dialog");
  dialog.dataset.itemId = item.id;
  $("#block-reason").value = item.blocked_reason || "";
  openDialog(dialog);
  $("#block-reason").focus();
}

function endDrag() {
  const drag = state.drag;
  state.drag = null;
  if (drag?.scrollFrame) cancelAnimationFrame(drag.scrollFrame);
  if (drag?.handle.hasPointerCapture(drag.pointerId)) drag.handle.releasePointerCapture(drag.pointerId);
  document.body.classList.remove("is-reordering");
  for (const node of document.querySelectorAll(".is-dragging,.drop-before,.drop-after")) node.classList.remove("is-dragging", "drop-before", "drop-after");
}

function startPointerDrag(event, item, card, queueItems) {
  if (state.pending || state.boardUnreadable || !event.isPrimary || event.button !== 0 || queueItems.length < 2) return;
  event.preventDefault();
  endDrag();
  const handle = event.currentTarget;
  state.drag = {
    id: item.id, ids: queueItems.map(entry => entry.id), revision: state.board.revision,
    pointerId: event.pointerId, startX: event.clientX, startY: event.clientY,
    clientX: event.clientX, clientY: event.clientY, active: false, targetId: null,
    after: false, handle, card, scrollFrame: null,
  };
  handle.setPointerCapture(event.pointerId);
}

function updateDragTarget() {
  const drag = state.drag;
  if (!drag?.active) return;
  for (const node of document.querySelectorAll(".drop-before,.drop-after")) node.classList.remove("drop-before", "drop-after");
  drag.targetId = null;
  const queue = $("#queue");
  const bounds = queue.getBoundingClientRect();
  if (drag.clientX < bounds.left - 20 || drag.clientX > bounds.right + 20 || drag.clientY < bounds.top - 36 || drag.clientY > bounds.bottom + 36) return;
  const cards = Array.from(queue.querySelectorAll(".queue-card")).filter(card => card.dataset.itemId !== drag.id);
  if (!cards.length) return;
  let target = cards.find(card => {
    const rect = card.getBoundingClientRect();
    return drag.clientY < rect.top + rect.height / 2;
  });
  drag.after = !target;
  if (!target) target = cards[cards.length - 1];
  drag.targetId = target.dataset.itemId;
  target.classList.add(drag.after ? "drop-after" : "drop-before");
}

function scrollDuringDrag() {
  const drag = state.drag;
  if (!drag?.active) return;
  const direction = drag.clientY < 72 ? -1 : drag.clientY > window.innerHeight - 72 ? 1 : 0;
  if (direction) {
    window.scrollBy(0, direction * 9);
    updateDragTarget();
  }
  drag.scrollFrame = requestAnimationFrame(scrollDuringDrag);
}

function movePointerDrag(event) {
  const drag = state.drag;
  if (!drag || event.pointerId !== drag.pointerId) return;
  event.preventDefault();
  drag.clientX = event.clientX;
  drag.clientY = event.clientY;
  if (!drag.active) {
    if (Math.hypot(event.clientX - drag.startX, event.clientY - drag.startY) < 5) return;
    drag.active = true;
    drag.card.classList.add("is-dragging");
    document.body.classList.add("is-reordering");
    drag.scrollFrame = requestAnimationFrame(scrollDuringDrag);
  }
  updateDragTarget();
}

function finishPointerDrag(event) {
  const drag = state.drag;
  if (!drag || event.pointerId !== drag.pointerId) return;
  event.preventDefault();
  drag.clientX = event.clientX;
  drag.clientY = event.clientY;
  updateDragTarget();
  if (!drag.active || !drag.targetId) { endDrag(); return; }
  const ids = drag.ids.filter(id => id !== drag.id);
  ids.splice(ids.indexOf(drag.targetId) + (drag.after ? 1 : 0), 0, drag.id);
  endDrag();
  if (ids.every((id, index) => id === drag.ids[index])) return;
  mutate("reorder", { ids }, { revision: drag.revision, focus: `${drag.id}:move-up`, success: "Queue order saved." });
}

window.addEventListener("blur", endDrag);
window.addEventListener("keydown", event => { if (event.key === "Escape" && state.drag) endDrag(); });

$("#add-feedback").addEventListener("click", () => openFeedback());
for (const button of document.querySelectorAll(".dialog-close")) button.addEventListener("click", () => button.closest("dialog").close());
for (const dialog of document.querySelectorAll("dialog")) dialog.addEventListener("cancel", event => { if (state.pending) event.preventDefault(); });

$("#feedback-form").addEventListener("submit", async event => {
  event.preventDefault();
  const dialog = $("#feedback-dialog");
  const title = $("#feedback-title").value.trim();
  if (!title) { showError("Give this feedback a title.", dialog); $("#feedback-title").focus(); return; }
  const source = $("#feedback-source").value.trim();
  if (source) {
    try { if (!["http:", "https:"].includes(new URL(source).protocol)) throw new Error(); }
    catch (_) { showError("Source links must start with http:// or https://.", dialog); return; }
  }
  const payload = { title, notes: $("#feedback-notes").value, build_id: $("#feedback-build").value.trim(), source_link: source };
  if (dialog.dataset.itemId) payload.id = dialog.dataset.itemId;
  await mutate(payload.id ? "edit" : "add", payload, { dialog, revision: Number(dialog.dataset.revision) });
});

$("#block-form").addEventListener("submit", event => {
  event.preventDefault();
  const dialog = $("#block-dialog");
  const reason = $("#block-reason").value.trim();
  if (!reason) { showError("Describe what is blocking this feedback.", dialog); return; }
  mutate("status", { id: dialog.dataset.itemId, status: "blocked", blocked_reason: reason, user_override: true }, { dialog, revision: Number(dialog.dataset.revision) });
});

$("#start-work").addEventListener("click", () => {
  if (state.selection?.kind !== "next") return;
  const dialog = $("#claim-dialog");
  dialog.dataset.itemId = state.selection.item.id;
  $("#claim-description").textContent = `Record ownership of “${state.selection.item.title}” for an existing development task. Claiming records the assignment on this board; it does not launch a task.`;
  try { $("#claim-owner").value = localStorage.getItem("feedback-task-owner") || ""; }
  catch (_) { $("#claim-owner").value = ""; }
  openDialog(dialog);
  $("#claim-owner").focus();
});

$("#claim-form").addEventListener("submit", async event => {
  event.preventDefault();
  const dialog = $("#claim-dialog");
  const owner = $("#claim-owner").value.trim();
  if (!owner) { showError("Enter the owning task identifier.", dialog); return; }
  const saved = await mutate("claim", { owner, id: dialog.dataset.itemId }, { dialog, revision: Number(dialog.dataset.revision), success: "Development claim saved." });
  if (saved) { try { localStorage.setItem("feedback-task-owner", owner); } catch (_) { /* Optional convenience only. */ } }
});

$("#restore-board").addEventListener("click", () => { $("#restore-file").value = ""; $("#restore-file").click(); });
$("#restore-file").addEventListener("change", async event => {
  const file = event.target.files[0];
  if (!file) return;
  try {
    if (file.size > 20 * 1024 * 1024) throw new Error("Choose a feedback JSON file smaller than 20 MiB.");
    const parsed = JSON.parse(await file.text());
    const board = parsed.board || parsed;
    if (!board || !Array.isArray(board.items)) throw new Error("This file does not contain a feedback board.");
    const dialog = $("#restore-dialog");
    dialog.restoreBoard = board;
    dialog.dataset.mode = "restore";
    $("#restore-dialog-title").textContent = "Restore feedback";
    $("#restore-description").textContent = `Restore ${board.items.length} feedback ${board.items.length === 1 ? "item" : "items"} from “${file.name}”?`;
    $(".restore-warning", dialog).textContent = "This replaces the current board, including its order and development claims. The current board is retained as a recovery backup.";
    openDialog(dialog);
  } catch (error) { showError(error instanceof SyntaxError ? "This file is not valid JSON. The current board has not changed." : error.message); }
});

$("#recover-board").addEventListener("click", () => {
  const dialog = $("#restore-dialog");
  dialog.dataset.mode = "recover";
  $("#restore-dialog-title").textContent = "Recover the backup";
  $("#restore-description").textContent = "Load the previous saved version of this feedback board?";
  $(".restore-warning", dialog).textContent = "The backup replaces the current board. Download the backup first if you would like to inspect it. Recovery errors leave your files intact.";
  openDialog(dialog);
});

$("#restore-form").addEventListener("submit", event => {
  event.preventDefault();
  const dialog = $("#restore-dialog");
  const recover = dialog.dataset.mode === "recover";
  mutate(recover ? "recover" : "restore", recover ? {} : { board: dialog.restoreBoard }, { dialog, revision: state.boardUnreadable ? -1 : Number(dialog.dataset.revision), success: recover ? "Backup recovered." : "Feedback board restored." });
});

async function initialize() {
  $("#queue").append(element("p", "loading-placeholder", "Loading feedback…"));
  setPending(true);
  try {
    state.token = (await request("/api/session")).token;
    await refreshBoard({ announce: true });
  } catch (error) {
    $("#queue").replaceChildren(emptyState("The board could not be loaded", "Your feedback has not been changed. Check the local server or recover a saved backup."));
    $("#selection-title").textContent = "Feedback is currently unavailable";
    $("#selection-description").textContent = "Resolve the load error to view the next development item.";
    showError(error.message);
    showStatus("Board could not be loaded.", "error");
  } finally { setPending(false); }

  window.setInterval(async () => {
    if (state.pending || state.drag || document.hidden) return;
    try {
      const previouslyConnected = state.connected;
      await refreshBoard();
      if (!previouslyConnected) {
        clearError();
        showStatus("Connected · latest feedback loaded");
      }
    } catch (error) {
      state.connected = false;
      showStatus("Cannot refresh the board. Check the local server.", "error");
    }
  }, 5000);
}

initialize();
