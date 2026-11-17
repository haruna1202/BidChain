async function readResponse(response) {
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.message || `API lỗi (${response.status}).`);
  return body;
}

export async function fetchCardsByChainIds(chainCardIds) {
  const ids = [...new Set(chainCardIds.map(String))];
  if (!ids.length) return [];
  const query = new URLSearchParams({ chainCardIds: ids.join(',') });
  return readResponse(await fetch(`/api/cards?${query}`));
}

export async function saveCardToDatabase({ chainCardId, sellerAddress, profile, certificateKey, metadataHash, transactionHash, files }) {
  const body = new FormData();
  body.append('chainCardId', String(chainCardId));
  body.append('profileId', String(profile.profileId));
  body.append('sellerAddress', sellerAddress);
  body.append('profileJson', JSON.stringify(profile));
  body.append('certificateKey', certificateKey);
  body.append('metadataHash', metadataHash);
  body.append('transactionHash', transactionHash || '');
  body.append('front', files.front);
  body.append('back', files.back);
  body.append('certificateFile', files.certificate);
  return readResponse(await fetch('/api/cards', { method: 'POST', body }));
}

export async function checkApiHealth() {
  return readResponse(await fetch('/api/health'));
}
