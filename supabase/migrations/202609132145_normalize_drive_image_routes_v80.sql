-- CV Coach V80
-- Normalize active Google Drive exercise-image URLs to the thumbnail endpoint.
-- The legacy uc?export=view endpoint was not reliable for <img> decoding in the client portal.
-- Idempotent: rows already using /thumbnail are untouched.

update public.exercises
set image_path = 'https://drive.google.com/thumbnail?id='
  || substring(image_path from 'id=([^&]+)')
  || '&sz=w1600'
where active is true
  and image_path like 'https://drive.google.com/uc?export=view&id=%';
