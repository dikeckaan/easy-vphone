#!/usr/bin/env python3
"""Publish aggregate GitHub counters only; credentials stay in gh/Actions."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

REPO = 'dikeckaan/easy-vphone'
START = '<!-- metrics:start -->'
END = '<!-- metrics:end -->'


def api(path, paginate=False):
    cmd = ['gh','api',f'repos/{REPO}/{path}'.rstrip('/')]
    if paginate:
        cmd += ['--paginate','--slurp']
    result = subprocess.run(cmd,capture_output=True,text=True,timeout=60)
    if result.returncode:
        raise RuntimeError('GitHub data unavailable')
    value = json.loads(result.stdout)
    return [x for page in value for x in page] if paginate else value


def merge_daily(existing, incoming):
    # Replace overlapping days: never add overlapping 14-day snapshots together.
    days = {item['timestamp']:item for item in existing}
    for item in incoming:
        days[item['timestamp']] = {k:item[k] for k in ('timestamp','count','uniques')}
    return sorted(days.values(),key=lambda x:x['timestamp'])


def collect(previous):
    now = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    result = dict(previous)
    result['updated_at'] = now
    repo = api('')
    result['repository'] = {k:repo[k] for k in ('stargazers_count','forks_count','subscribers_count','open_issues_count')}
    releases = api('releases?per_page=100',paginate=True)
    result['releases'] = [
        {'version':r['tag_name'],'prerelease':r['prerelease'], 'assets':[
            {'name':a['name'],'downloads':a['download_count'],'bytes':a['size']}
            for a in r['assets']]} for r in releases if not r['draft']]
    for kind in ('clones','views'):
        try:
            data = api('traffic/'+kind)
            result[kind] = {'updated_at':now,'count':data['count'],'uniques':data['uniques'],
                            'daily':merge_daily(previous.get(kind,{}).get('daily',[]),data[kind])}
            result.pop(kind+'_error',None)
        except RuntimeError:
            # Keep the previous timestamp and numbers; never substitute zero.
            result[kind+'_error'] = 'Traffic API unavailable to this collector; last successful snapshot retained.'
    return result


def downloads(data):
    return sum(a['downloads'] for r in data['releases'] for a in r['assets'] if a['name'].endswith('.zip'))


def summary(data):
    repo = data['repository']
    lines = ['## Project statistics','',f"Updated: **{data['updated_at']}**. Counts are events, not installs or people.",'',
             '| Metric | Count |','|---|---:|',f"| ZIP downloads across releases | {downloads(data)} |",
             f"| Stars | {repo['stargazers_count']} |",f"| Forks | {repo['forks_count']} |",
             f"| Watchers | {repo['subscribers_count']} |",f"| Open issues + pull requests | {repo['open_issues_count']} |"]
    for kind,label in [('clones','Clones'),('views','Page views')]:
        item=data.get(kind)
        if item:
            lines += [f"| {label}, last 14-day snapshot | {item['count']} |",f"| Unique {'cloners' if kind=='clones' else 'visitors'}, same snapshot | {item['uniques']} |"]
        else:
            lines.append(f'| {label}, last 14 days | Unavailable |')
    lines += ['','[Detailed release downloads, daily clone/view history and collection timestamps](METRICS.md).',
              'GitHub does not expose unique downloaders. Clone/view uniqueness is limited to the reported window; daily uniques must not be summed as people.',
              'Automated builds and verification downloads can contribute to these counters.']
    return '\n'.join(lines)


def render(data, root):
    (root/'metrics').mkdir(exist_ok=True)
    (root/'metrics/data.json').write_text(json.dumps(data,indent=2)+'\n')
    readme=root/'README.md'; content=readme.read_text()
    section=START+'\n'+summary(data)+'\n'+END
    if START in content and END in content:
        content=content[:content.index(START)]+section+content[content.index(END)+len(END):]
    else:
        content+='\n'+section+'\n'
    readme.write_text(content)
    lines=['# easy-vphone metrics','',summary(data),'','## Release assets','',
           '| Release | Asset | Downloads | Bytes |','|---|---|---:|---:|']
    for release in data['releases']:
        for asset in release['assets']:
            # Names are controlled by maintainers; escape table delimiters anyway.
            name=asset['name'].replace('|','\\|').replace('\n',' ')
            lines.append(f"| {release['version']} | {name} | {asset['downloads']} | {asset['bytes']} |")
    for kind,label in [('clones','Clones'),('views','Page views')]:
        lines+=['',f'## {label}','']
        if kind not in data:
            lines+=['Unavailable. No traffic snapshot has been collected.']; continue
        item=data[kind]
        lines += [f"Last successful traffic snapshot: **{item['updated_at']}**.",
                  f"14-day total: **{item['count']}**; unique {'cloners' if kind=='clones' else 'visitors'}: **{item['uniques']}**."]
        if kind+'_error' in data:
            lines+=['',data[kind+'_error']]
        lines+=['','Archived daily counters (UTC; newest day can be incomplete). These are events, not lifetime unique people.','',
                '| Day | Events | Unique that day |','|---|---:|---:|']
        for day in reversed(item['daily']):
            lines.append(f"| {day['timestamp'][:10]} | {day['count']} | {day['uniques']} |")
    lines+=['','## Collection and limitations','',
            '- Public release/stars/forks counters refresh every six hours through GitHub Actions.',
            '- Traffic requires additional repository access. If Actions cannot read it, the last successful snapshot and its timestamp remain visible.',
            '- The owner’s Mac refreshes traffic every six hours while logged in and online, using its existing gh session. If the Mac is off, the last snapshot remains visible. No account token is committed or copied into repository secrets.',
            '- GitHub exposes only the last 14 days of traffic. Daily snapshots are merged by UTC date to avoid double-counting; missed days older than that cannot be recovered.',
            '- ZIP downloads include manual downloads, Homebrew downloads and validation downloads. They do not count installs or unique people.',
            '- Source ZIP downloads and git clones are different metrics. There is no lifetime unique clone/download count here.',
            '- No telemetry is collected from the app. Update checks only request public release metadata from GitHub.',
            '', '[GitHub traffic API](https://docs.github.com/en/rest/metrics/traffic) · [Release asset API](https://docs.github.com/en/rest/releases/assets)', '']
    (root/'METRICS.md').write_text('\n'.join(lines))


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]); args=parser.parse_args()
    path=args.root/'metrics/data.json'
    previous=json.loads(path.read_text()) if path.exists() else {}
    render(collect(previous),args.root)

if __name__=='__main__':
    main()
