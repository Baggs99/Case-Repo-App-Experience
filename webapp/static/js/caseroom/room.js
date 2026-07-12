/**
 * Purpose: room-page actions (spec §4.7) — queue removal, proposal
 *          accept/decline with time pick, and the propose modal on visits.
 * Inputs: window.ROOM {ownerId, isOwn}; data-* hooks rendered by room.html;
 *         /api/queues, /api/proposals endpoints.
 * Outputs: POST/DELETE calls; page reloads on success (server re-renders
 *          the panels — no client-side state to keep in sync).
 * Run: loaded by room.html.
 */

(function () {
  const post = async (url, body) => {
    const res = await fetch(url, {
      method: 'POST',
      headers: body ? { 'Content-Type': 'application/json' } : {},
      body: body ? JSON.stringify(body) : undefined,
    });
    return { ok: res.ok, data: await res.json().catch(() => null) };
  };

  // Proposed-time pills: render ISO stamps in the viewer's local time, and
  // reflect the picked pill visually.
  for (const span of document.querySelectorAll('[data-iso]')) {
    const d = new Date(span.dataset.iso);
    if (!Number.isNaN(d.valueOf())) {
      span.textContent = d.toLocaleString([], {
        weekday: 'short', month: 'short', day: 'numeric',
        hour: '2-digit', minute: '2-digit',
      });
    }
  }
  for (const group of document.querySelectorAll('[data-times]')) {
    group.addEventListener('change', () => {
      for (const label of group.querySelectorAll('label')) {
        const on = label.querySelector('input').checked;
        label.classList.toggle('btn-pill-active', on);
        label.classList.toggle('btn-pill-default', !on);
      }
    });
  }

  // ── Own room: queues + inbox ───────────────────────────────────────────

  for (const btn of document.querySelectorAll('[data-unqueue]')) {
    btn.addEventListener('click', async () => {
      const [kind, caseId] = btn.dataset.unqueue.split(':');
      const res = await fetch(`/api/queues/${kind}/${caseId}`, { method: 'DELETE' });
      if (res.ok) location.reload();
    });
  }

  for (const btn of document.querySelectorAll('[data-accept]')) {
    btn.addEventListener('click', async () => {
      const id = btn.dataset.accept;
      const picked = document.querySelector(`input[name="time-${id}"]:checked`);
      const body = picked && picked.value ? { scheduled_at: picked.value } : {};
      btn.disabled = true;
      const { ok, data } = await post(`/api/proposals/${id}/accept`, body);
      if (!ok) { btn.disabled = false; return; }
      location.href = data.session_url; // straight to the new session page
    });
  }

  for (const btn of document.querySelectorAll('[data-decline]')) {
    btn.addEventListener('click', async () => {
      btn.disabled = true;
      const { ok } = await post(`/api/proposals/${btn.dataset.decline}/decline`);
      if (ok) location.reload(); else btn.disabled = false;
    });
  }

  // ── Visiting: propose modal ────────────────────────────────────────────

  const modal = document.getElementById('propose-modal');
  if (!modal) return;
  let current = null; // {caseId, role}

  for (const btn of document.querySelectorAll('[data-propose]')) {
    btn.addEventListener('click', () => {
      current = { caseId: Number(btn.dataset.propose), role: btn.dataset.role, btn };
      document.getElementById('propose-title').textContent =
        `Propose: ${btn.dataset.title}`;
      document.getElementById('propose-role-line').textContent =
        current.role === 'interviewer'
          ? 'You would run the case as interviewer.'
          : 'You would receive the case as candidate.';
      document.getElementById('propose-error').classList.add('hidden');
      modal.classList.remove('hidden');
      modal.classList.add('flex');
    });
  }

  const closeModal = () => {
    modal.classList.add('hidden');
    modal.classList.remove('flex');
  };
  document.getElementById('propose-cancel').addEventListener('click', closeModal);
  modal.addEventListener('click', (ev) => { if (ev.target === modal) closeModal(); });

  document.getElementById('propose-send').addEventListener('click', async () => {
    if (!current) return;
    const times = [...document.querySelectorAll('[data-propose-time]')]
      .map((input) => input.value)
      .filter(Boolean)
      .map((v) => new Date(v).toISOString());
    const { ok, data } = await post('/api/proposals', {
      to_user_id: window.ROOM.ownerId,
      case_id: current.caseId,
      from_role: current.role,
      message: document.getElementById('propose-message').value || null,
      proposed_times: times,
    });
    if (!ok) {
      const err = document.getElementById('propose-error');
      err.textContent = data?.detail || 'Could not send the proposal.';
      err.classList.remove('hidden');
      return;
    }
    closeModal();
    current.btn.textContent = 'Proposed ✓';
    current.btn.disabled = true;
  });
})();
