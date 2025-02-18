-- helpful flows that can be mapped to key bindings
-- they can assume sensible defaults and/or interact with the user
local flows = {}

local buffer = require('nvim-magic._buffer')
local keymaps = require('nvim-magic._keymaps')
local log = require('nvim-magic._log')
local templates = require('nvim-magic._templates')
local ui = require('nvim-magic._ui')

local function notify_prefix(filename)
	local prefix
	if 1 <= #filename then
		prefix = string.format('%s - ', filename)
	else
		prefix = '(buffer) -'
	end
	return prefix
end

function flows.append_completion(backend, max_tokens, stops)
	assert(backend ~= nil, 'backend must be provided')
	if max_tokens then
		assert(type(max_tokens) == 'number', 'max tokens must be a number')
		assert(1 <= max_tokens, 'max tokens must be at least 1')
	else
		max_tokens = 3000
	end
	if stops then
		assert(type(stops) == 'table', 'stop must be an array of strings')
		assert(type(stops[1]) == 'string', 'stop must be an array of strings')
	end

	local orig_bufnr, orig_winnr = buffer.get_handles()
	local filename = buffer.get_filename()
	local nprefix = notify_prefix(filename)

	local visual_lines, _, _, end_row, end_col = buffer.get_visual_lines()
	if not visual_lines then
		ui.notify(nprefix .. 'nothing selected')
		return
	end

	log.fmt_debug('Fetching completion max_tokens=%s stops=%s', max_tokens, vim.inspect(stops))
	ui.notify(nprefix .. 'fetching completion... max_tokens=' .. max_tokens)
	backend:complete(visual_lines, max_tokens, stops, function(completion)
		local compl_lines = vim.split(completion, '\n', true)

		buffer.append(orig_bufnr, end_row, compl_lines)
		vim.api.nvim_set_current_win(orig_winnr)
		vim.api.nvim_set_current_buf(orig_bufnr)
		vim.api.nvim_win_set_cursor(0, { end_row, end_col }) -- TODO: use specific window

		ui.notify(nprefix .. 'fetched completion (' .. tostring(#completion) .. ' characters)', 'info')
	end, function(errmsg)
		ui.notify(nprefix .. errmsg)
	end)
end

function flows.suggest_alteration(backend, language)
	assert(backend ~= nil, 'backend must be provided')
	if not language then
		language = buffer.get_filetype()
	else
		assert(type(language) == 'string', 'language must be a string')
	end

	local orig_bufnr, orig_winnr = buffer.get_handles()
	local filename = buffer.get_filename()
	local nprefix = notify_prefix(filename)

	local visual_lines, start_row, start_col, end_row, _ = buffer.get_visual_lines()
	if not visual_lines then
		ui.notify(nprefix .. 'nothing selected')
		return
	end

	ui.prompt_input('This code should be altered to...', keymaps.get_quick_quit(), function(task)
		local visual = table.concat(visual_lines, '\n')
		local tmpl = templates.loaded.alter
		local prompt = tmpl:fill({
			language = language,
			task = task,
			snippet = visual,
		})
		local prompt_lines = vim.fn.split(prompt, '\n', false)
		-- we default max tokens to a "large" value in case the prompt is large, this isn't robust
		-- ideally we would estimate the number of tokens in the prompt and then set a max tokens
		-- value proportional to that (e.g. 2x) and taking into account the max token limit as well
		local max_tokens = 3000
		local stops = { tmpl.stop_code }

		log.fmt_debug('Fetching alteration max_tokens=%s stops=%s', max_tokens, vim.inspect(stops))
		ui.notify(nprefix .. string.format('fetching suggested alteration (task=%s)', task))
		backend:complete(prompt_lines, max_tokens, stops, function(completion)
			ui.notify(nprefix .. 'fetched suggested alteration (' .. tostring(#completion) .. ' characters)', 'info')
			local compl_lines = vim.split(completion, '\n', true)
			vim.api.nvim_set_current_win(orig_winnr)
			vim.api.nvim_set_current_buf(orig_bufnr)

			ui.pop_up(
				compl_lines,
				language,
				{
					top = 'Suggested alteration',
					top_align = 'center',
					bottom = '[a] - append | [p] paste over',
					bottom_align = 'left',
				},
				vim.list_extend(keymaps.get_quick_quit(), {
					{
						'n',
						'a', -- append to original buffer
						function(_)
							buffer.append(orig_bufnr, end_row, compl_lines)
							vim.api.nvim_win_close(0, true)
						end,
						{ noremap = true },
					},
					{
						'n',
						'p', -- replace in original buffer
						function(_)
							buffer.paste_over(orig_bufnr, start_row, start_col, end_row, compl_lines)
							vim.api.nvim_win_close(0, true)
						end,
						{ noremap = true },
					},
				})
			)
		end, function(errmsg)
			ui.notify(nprefix .. errmsg)
		end)
	end)
end

function flows.suggest_docstring(backend, language)
	assert(backend ~= nil, 'backend must be provided')
	if not language then
		language = buffer.get_filetype()
	else
		assert(type(language) == 'string', 'language must be a string')
	end

	local orig_bufnr, orig_winnr = buffer.get_handles()
	local filename = buffer.get_filename()
	local nprefix = notify_prefix(filename)

	local vis_lines, start_row, start_col, end_row, _ = buffer.get_visual_lines()
	if not vis_lines then
		ui.notify(nprefix .. 'nothing selected')
		return
	end

	local visual = table.concat(vis_lines, '\n')
	local tmpl = templates.loaded.docstring
	local prompt = tmpl:fill({
		language = language,
		snippet = visual,
	})
	local prompt_lines = vim.fn.split(prompt, '\n', false)
	-- we default max tokens to a "large" value in case the prompt is large, this isn't robust
	-- ideally we would estimate the number of tokens in the prompt and then set a max tokens
	-- value proportional to that (e.g. 2x) and taking into account the max token limit as well
	local max_tokens = 3000
	local stops = { tmpl.stop_code }

	log.fmt_debug('Fetching docstring max_tokens=%s stops=%s', max_tokens, tostring(stops))
	ui.notify(nprefix .. 'fetching suggested docstring...')
	backend:complete(prompt_lines, max_tokens, stops, function(completion)
		ui.notify(nprefix .. 'fetched suggested docstring (' .. tostring(#completion) .. ' characters)', 'info')
		local compl_lines = vim.split(completion, '\n', true)
		vim.api.nvim_set_current_win(orig_winnr)
		vim.api.nvim_set_current_buf(orig_bufnr)

		ui.pop_up(
			compl_lines,
			language,
			{
				top = 'Suggested alteration',
				top_align = 'center',
				bottom = '[a] - append | [p] paste over',
				bottom_align = 'left',
			},
			vim.list_extend(keymaps.get_quick_quit(), {
				{
					'n',
					'a', -- append to original buffer
					function(_)
						buffer.append(orig_bufnr, end_row, compl_lines)
						vim.api.nvim_win_close(0, true)
					end,
					{ noremap = true },
				},
				{
					'n',
					'p', -- replace in original buffer
					function(_)
						buffer.paste_over(orig_bufnr, start_row, start_col, end_row, compl_lines)
						vim.api.nvim_win_close(0, true)
					end,
					{ noremap = true },
				},
			})
		)
	end, function(errmsg)
		ui.notify(nprefix .. errmsg)
	end)
end

-- a Lua function that outputs all key value pairs in a table, even if the table contains tables
function printTable(t)
  if t == nil then return end -- added line to check if t is nil
  for k, v in pairs(t) do
    if type(v) == "table" then
      print(k .. ":")
      printTable(v)
    else
      print(k .. ": " .. tostring(v))
    end
  end
end

function flows.suggest_chat(backend, language)
	assert(backend ~= nil, 'backend must be provided')
	max_tokens = 3000
	local orig_bufnr, orig_winnr = buffer.get_handles()
	local filename = buffer.get_filename()
	local nprefix = notify_prefix(filename)

  -- check if chat history is zero, set backend chat buffer to orig_bufnr
  if backend:get_chat_length() == 0 then
    backend:set_chat_buffer(orig_bufnr)
  end

	local visual_lines, start_row, start_col, end_row, _ = buffer.get_visual_lines()
  printTable(visual_lines)


	ui.prompt_input('What is your question? ...', keymaps.get_quick_quit(), function(task)
    local prompt

    if visual_lines == nil then
      prompt = task
    else
      prompt = "Here is some context.\n" .. table.concat(visual_lines, "\n") .. "\nnow, " .. task
    end

    buffer.append_end(backend:get_chat_buffer(), ">> " .. task)
    log.fmt_debug('Fetching completion max_tokens=%s', max_tokens)
    backend:chat(prompt, max_tokens, function(completion)
      buffer.append_end(backend:get_chat_buffer(), completion)
      --vim.api.nvim_set_current_win(orig_winnr)
      --vim.api.nvim_set_current_buf(orig_bufnr)
      --vim.api.nvim_win_set_cursor(0, { end_row, end_col }) -- TODO: use specific window

      ui.notify(nprefix .. 'fetched completion (' .. tostring(#completion) .. ' characters)', 'info')
    end, function(errmsg)
      ui.notify(nprefix .. errmsg)
    end)

	end)
end

function flows.suggest_chat_reset(backend, language)
  backend:chat_reset()
  print("Chat has been reset")
end





return flows
