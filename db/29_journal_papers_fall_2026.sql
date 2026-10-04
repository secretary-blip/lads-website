-- ---------------------------------------------------------------------------
-- 29. The first two Journal Club papers, autumn 2026
--
-- Five sessions this semester, every two weeks from 13 October: 13 Oct,
-- 27 Oct, 10 Nov, 24 Nov and 8 Dec. 22 December is skipped for finals. One
-- presenter each session. Papers are added as the committee chooses them, so
-- only the two chosen so far are written here; the other three dates have no
-- row until they do.
--
-- Both papers are cross-sectional studies. The first arrived named "RCT", which
-- it is not: it is an observational survey with a clinical exam. The study
-- design is what the "Question it" part of a session turns on, so it is stated
-- in each summary rather than left to the file name.
--
-- Presenter is left empty on both until the committee names them. The page
-- shows nothing in that slot rather than a guess.
--
-- The placeholder row written while testing the setup guide is removed by its
-- exact title, so nothing real can be caught by it.
-- ---------------------------------------------------------------------------

delete from public.journal_papers where title = 'The corrected title';

insert into public.journal_papers
  (session_on, topic, title, journal, pub_year, doi, url, summary, presenter, published)
values
  ('2026-10-13',
   'Periodontics',
   'The effect of cigarette and e-cigarette use on periodontal health: A cross-sectional study in Eastern Province, Saudi Arabia',
   'Tobacco Induced Diseases',
   2026,
   '10.18332/tid/209573',
   'https://doi.org/10.18332/tid/209573',
   'A cross-sectional study of 169 adults in Saudi Arabia comparing periodontal disease in cigarette smokers, e-cigarette users and non-smokers. Cigarette smokers had sharply higher odds of disease. E-cigarette users had raised odds too, but the confidence interval is wide and crosses no effect, which is the part worth arguing about.',
   null,
   true),
  ('2026-10-27',
   'Dental anxiety',
   'Dental Anxiety and Oral Health-Related Quality of Life Among Adults in the United Arab Emirates: A Cross-Sectional Study',
   'Healthcare',
   2026,
   '10.3390/healthcare14020219',
   'https://doi.org/10.3390/healthcare14020219',
   'Adult patients at a university dental clinic in the UAE, scored on the Modified Dental Anxiety Scale and the OHIP-14. Higher anxiety went with worse oral health-related quality of life after adjusting for age and gender. A modest convenience sample, so an association, not a cause.',
   null,
   true)
on conflict (session_on) do update
   set topic = excluded.topic, title = excluded.title, journal = excluded.journal,
       pub_year = excluded.pub_year, doi = excluded.doi, url = excluded.url,
       summary = excluded.summary, published = excluded.published,
       updated_at = now();

select session_on, topic, left(title, 60) as title, journal, published
  from public.journal_papers
 order by session_on;
