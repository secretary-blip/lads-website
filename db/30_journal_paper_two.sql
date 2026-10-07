-- ---------------------------------------------------------------------------
-- 30. The second Journal Club paper changes
--
-- The committee replaced the 27 October paper. The dental anxiety study from
-- the UAE is out; a systematic review and meta-analysis on sugar-free chewing
-- gum and caries is in. Only the 27 October row changes. Presenter stays empty
-- until the committee names one.
-- ---------------------------------------------------------------------------

update public.journal_papers
   set topic      = 'Cariology',
       title      = 'A Systematic Review and Meta-Analysis of the Role of Sugar-Free Chewing Gum in Dental Caries',
       journal    = 'JDR Clinical & Translational Research',
       pub_year   = 2020,
       doi        = '10.1177/2380084419887178',
       url        = 'https://doi.org/10.1177/2380084419887178',
       summary    = 'Twelve studies, eleven of them randomised trials, mostly in children aged 6 to 14. Chewing sugar-free gum prevented about 28% of caries (95% CI 7% to 48%). No study was at low risk of bias across all domains, the doses varied widely and the review was funded by a gum maker, which is the part worth arguing about.',
       published  = true,
       updated_at = now()
 where session_on = '2026-10-27';

select session_on, topic, left(title, 60) as title, journal, published
  from public.journal_papers
 order by session_on;
