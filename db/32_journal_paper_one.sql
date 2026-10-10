-- ---------------------------------------------------------------------------
-- 32. The first Journal Club paper changes
--
-- Nour chose a different paper for 13 October. The e-cigarette study from
-- Saudi Arabia is out; a randomised trial of immersive virtual reality during
-- extractions under local anaesthesia is in. Only the 13 October row changes.
-- Presenter stays empty until the committee names one.
-- ---------------------------------------------------------------------------

update public.journal_papers
   set topic      = 'Oral surgery',
       title      = 'The Effect of Immersive Virtual Reality on Dental Anxiety and Intraoperative Pain in Adults Undergoing Local Anesthesia: A Randomized Clinical Trial',
       journal    = 'Healthcare',
       pub_year   = 2024,
       doi        = '10.3390/healthcare12232424',
       url        = 'https://doi.org/10.3390/healthcare12232424',
       summary    = 'A single-blind randomised trial of 190 anxious adults having extractions under local anaesthesia at a private clinic in Almeria, Spain. Patients who wore a virtual reality headset reported less anxiety and less pain, and had lower heart rate and blood pressure, than the control group. The patients knew which group they were in and it is one clinic, which is the part worth arguing about.',
       published  = true,
       updated_at = now()
 where session_on = '2026-10-13';

select session_on, topic, left(title, 60) as title, journal, published
  from public.journal_papers
 order by session_on;
