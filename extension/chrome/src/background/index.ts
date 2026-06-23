import { BackgroundSendService } from '@/services/background-send-service';
import { SendPollService } from '@/services/send-poll-service';

void BackgroundSendService.restoreAndResume();

chrome.runtime.onInstalled.addListener(() => {
  chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true }).catch(() => {});
});

chrome.alarms.create('pollSends', { periodInMinutes: 0.5 });

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === 'pollSends') {
    await SendPollService.pollPendingSends();
  }
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'POLL_SENDS') {
    SendPollService.pollPendingSends()
      .then(() => sendResponse({ ok: true }))
      .catch(() => sendResponse({ ok: false }));
    return true;
  }
  return false;
});
